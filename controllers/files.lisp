(in-package :turtl)

(defroute (:post "/api/filez" :chunk t :suppress-100 t :buffer-body t) (req res)
  (catch-errors (res)
    (let ((bytes (flexi-streams:make-in-memory-output-stream :element-type '(unsigned-byte 8)))
          (chunk-num 0))
      (when (string= (getf (request-headers req) :transfer-encoding) "chunked")
        (send-100-continue res))
      (with-chunking req (data lastp)
        (format t "- chunk: ~a~%---~%" (babel:octets-to-string data :encoding :utf-8))
        (write-sequence data bytes)
        (incf chunk-num)
        (when lastp
          (format t "done.~%")
          (send-json res (flex:get-output-stream-sequence bytes)))))))

(defun do-upload (req res file)
  "Abstraction function that handles chunking and streaming file contents to
   storage system."
  (catch-errors (res)
    (let* ((s3-uploader :starting)
           (user-id (user-id req))
           (file-id (gethash "id" file))
           (buffered-chunks nil)
           (path (format nil "/files/~a" (gethash "id" file)))
           (chunking-started nil)
           (last-chunk-sent nil)
           (total-file-size 0)
           (finish-fn (lambda ()
                        (format t "- file: sending final response to client~%")
                        (setf (gethash "size" file) total-file-size)
                        (remhash "upload_id" file)
                        (remhash "uploading" file)
                        (edit-file user-id file-id file)
                        (send-json res file))))
      ;; create an uploader lambda, used to stream our file chunk by chunk to S3
      (format t "- file: starting uploader with path: ~a~%" path)
      (multiple-future-bind (uploader upload-id)
          (s3-upload path)
        ;; save our file record
        (setf (gethash "upload_id" file) upload-id)
        (wait-for (edit-file user-id file-id file)
          (format t "- file: file saved: ~a~%" (gethash "id" file)))
        ;; save our uploader so the chunking brahs can use it
        (format t "- file: uploader created: ~a~%" upload-id)
        (setf s3-uploader uploader)
        ;; if we haven't started getting the body yet, let the client know it's
        ;; ok to send
        (unless chunking-started
          (send-100-continue res))
        (when last-chunk-sent
          (alet* ((body (flexi-streams:get-output-stream-sequence buffered-chunks))
                  (finishedp (funcall s3-uploader body)))
            (incf total-file-size (length body))   ; track the file size
            ;; note that finishedp should ALWAYS be true here, but "should" and
            ;; "will" are very different things (especially in async, i'm
            ;; finding)
            (when finishedp
              (funcall finish-fn)))))
      ;; listen for chunked data. if we have an uploader object, send in our
      ;; data directly, otherwise buffer it until the uploader becomes
      ;; available
      (format t "- file: calling with-chunking~%")
      (with-chunking req (chunk-data last-chunk-p)
        ;; notify the upload creator that chunking has started. this prevents it
        ;; from sending a 100 Continue header if the flow has already started.
        (setf chunking-started t
              last-chunk-sent (or last-chunk-sent last-chunk-p))
        (cond ((eq s3-uploader :starting)
               (unless buffered-chunks
                 (format t "- file: uploader not ready, buffering chunks~%")
                 (setf buffered-chunks (flexi-streams:make-in-memory-output-stream :element-type '(unsigned-byte 8))))
               (write-sequence chunk-data buffered-chunks))
              (t
               (when buffered-chunks
                 (write-sequence chunk-data buffered-chunks)
                 (setf chunk-data (flexi-streams:get-output-stream-sequence buffered-chunks)))
               (incf total-file-size (length chunk-data))   ; track the file size
               (alet ((finishedp (funcall s3-uploader chunk-data (not last-chunk-p))))
                 (when finishedp
                   (funcall finish-fn)))
               (setf buffered-chunks nil)))))))

(defroute (:post "/api/files" :chunk t :suppress-100 t :buffer-body t) (req res)
  "Upload a new file."
  (catch-errors (res)
    (alet* ((hash (get-var req "hash"))
            (user-id (user-id req))
            (file (make-file :hash hash))
            (file (add-file user-id file)))
      (do-upload req res file))))

(defroute (:put "/api/files/([0-9a-f]+)" :chunk t :suppress-100 t :buffer-body t) (req res args)
  "Replace a file's contents."
  (catch-errors (res)
    (alet* ((file-id (car args))
            (hash (get-var req "hash"))
            (file (make-file :id file-id :hash hash)))
      (do-upload req res file))))

