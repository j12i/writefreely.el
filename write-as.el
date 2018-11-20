;; -*- lexical-binding: t -*-
;;; write-as.el --- Push your Org files as markdown to write.as

;; Copyright (C) 2018 Daniel Gomez

;; Author: Daniel Gomez <d.gomez at posteo dot org>
;; Created: 2018-16-11
;; URL: https://github.com/dangom/write-as.el
;; Package-Requires: ((emacs "24.3") (org "9.0") (ox-gfm "0.0") (request "0.3"))
;; Version: 0.0.2
;; Keywords: convenience

;; This file is not part of GNU Emacs.

;;; Copyright Notice:

;; This program is free software: you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs.  If not, see <http://www.gnu.org/licenses/>.

;;; Commentary:

;; Please see "Readme.org" for detailed introductions.
;; The API Documentation can be found here:
;; <https://developers.write.as/docs/api/>

;;; Code:

(require 'ox-gfm)
(require 'json)
(require 'request)


(defvar write-as-api-endpoint "https://write.as/api"
  "URL of the write.as API posts endpoint")

(defvar write-as-request-default-header
  '(("Content-Type" . "application/json"))
  "Default request header")

(defvar write-as-auth-token nil
  "User authorization token.
  See https://developers.write.as/docs/api/ for instructions.")

(defvar write-as-always-confirm-submit t
  "When nil, ask for confirmation before submission.")


(defun write-as-api-get-post-url (post-id)
  (concat write-as-api-endpoint "/posts/" post-id))


(defun write-as-publication-link (post-id)
  (concat "https://write.as/" post-id ".md"))


;; from http://lists.gnu.org/archive/html/emacs-orgmode/2018-11/msg00134.html
(defun write-as-get-orgmode-keyword (key)
  "To get the #+TITLE of an org file, do
   (write-as-get-orgmode-keyword \"#+TITLE\")"
  (org-element-map (org-element-parse-buffer) 'keyword
    (lambda (k)
      (when (string= key (org-element-property :key k))
	      (org-element-property :value k)))
    nil t))

(defun write-as-generate-request-header ()
  "If a write-as-auth-token is available, then add
the authorization to the header."
  (if write-as-auth-token
      (cons `("Authorization" .
              ,(concat "Token " write-as-auth-token))
            write-as-request-default-header)
    write-as-request-default-header))


(defun write-as-org-to-md-string ()
  "Return the current Org buffer as a md string."
  (save-window-excursion
    (let* ((org-buffer (current-buffer))
           (md-buffer (org-gfm-export-as-markdown))
           (md-string
            (with-current-buffer md-buffer
              (buffer-substring-no-properties (point-min) (point-max)))))
      (set-buffer org-buffer)
      (kill-buffer md-buffer)
      md-string)))


(defun write-as-get-user-collections ()
  "Retrieve a user write-as collections"
  (if write-as-auth-token
      (let ((response (request-response-data
                       (request
                        (concat write-as-api-endpoint "/me/collections")
                        :type "GET"
                        :parser #'json-read
                        :headers (write-as-generate-request-header)
                        :sync t
                        :error (function*
                                (lambda (&key error-thrown &allow-other-keys&rest _)
                                  (message "Got error: %S" error-thrown)))))))
        (mapcar #'(lambda (x) (assoc-default 'alias x))
                (assoc-default 'data response)))
    (message "Cannot get user collections if not authenticated.")))



(defun write-as-json-encode-data (title body &optional post-token)
  "Encode data as json for request."
  (let* ((alist `(("title" . ,title)
                  ("body" . ,body)))
         (token-alist (if post-token
                          (cons `("token" . ,post-token) alist)
                        alist)))
    (json-encode token-alist)))


(defun write-as-post-publish-request (title body &optional collection)
  "Send POST request to the write.as API endpoint with title and body as data.
   Return parsed JSON response"
  (let ((endpoint
         (concat write-as-api-endpoint
                 (when collection (concat "/collections/" collection))
                 "/posts")))
    (request-response-data
     (request
      endpoint
      :type "POST"
      :parser #'json-read
      :data (write-as-json-encode-data title body)
      :headers (write-as-generate-request-header)
      :sync t
      :error (function*
              (lambda (&key error-thrown &allow-other-keys&rest _)
                (message "Got error: %S" error-thrown)))))))


;; To update a post
(defun write-as-post-update-request (post-id post-token title body)
  "Send POST request to the write.as API endpoint with title and body as data.
   Message post successfully updated."
  (request
   (write-as-api-get-post-url post-id)
   :type "POST"
   :parser #'json-read
   :data (write-as-json-encode-data title body post-token)
   :headers (write-as-generate-request-header)
   :success (function*
             (lambda (&key data &allow-other-keys)
               (message "Post successfully updated.")))
   :error (function*
           (lambda (&key error-thrown &allow-other-keys&rest _)
             (message "Got error: %S" (assoc-default 'code error-thrown))))))


(defun write-as-update-org-buffer-locals (post-id post-token)
  "Setq-local and add-file-local variables for write-as post"
  (setq-local write-as-post-id post-id)
  (add-file-local-variable 'write-as-post-id post-id)
  (setq-local write-as-post-token post-token)
  (add-file-local-variable 'write-as-post-token post-token))


(defun write-as-publish-buffer (&optional collection)
  "Publish the current Org buffer to write.as."
  (let* ((title (write-as-get-orgmode-keyword "TITLE"))
         (body (write-as-org-to-md-string))
         ;; POST the blogpost with title and body
         (response (write-as-post-publish-request title body collection))
         ;; Get the id and token from the response
         (post-id (assoc-default 'id (assoc 'data response)))
         (post-token (assoc-default 'token (assoc 'data response))))
    ;; Use setq-local as well because otherwise the local variables won't be
    ;; evaluated.
    (if post-id
        (write-as-update-org-buffer-locals post-id post-token)
      (error "Post ID missing. Request probably went wrong."))))


;;;###autoload
(defun write-as-publish-or-update ()
  (interactive)
  (when (or  write-as-always-confirm-submit
             (y-or-n-p "Do you really want to publish this file to write-as? "))
    (if (and (boundp 'write-as-post-id)
             (boundp 'write-as-post-token))
        (let ((title (write-as-get-orgmode-keyword "TITLE"))
              (body (write-as-org-to-md-string)))
          (write-as-post-update-request write-as-post-id
                                        write-as-post-token
                                        title
                                        body))
      (if write-as-auth-token
          (let* ((anonymous-collection "-- submit post anonymously --")
                 (collection
                  (completing-read "Submit post to which collection:"
                                   (cons
                                    anonymous-collection
                                    (write-as-get-user-collections)))))
            (if (string-equal anonymous-collection collection)
                (write-as-publish-buffer)
              (write-as-publish-buffer collection)))
        (write-as-publish-buffer)))))


;;;###autoload
(defun write-as-visit-post ()
  (interactive)
  (if (and (boundp 'write-as-post-id)
           (boundp 'write-as-post-token))
      (let ((browse-program
             (cond
              ((eq system-type 'darwin) "open")
              ((eq system-type 'linux) (executable-find "firefox")))))
        (shell-command
         (concat browse-program
                 " "
                 (write-as-publication-link write-as-post-id))))))


(provide 'write-as)
;;; write-as.el ends here
