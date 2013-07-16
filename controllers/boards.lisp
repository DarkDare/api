(in-package :tagit)

(defroute (:get "/api/boards/users/([0-9a-f-]+)") (req res args)
  (catch-errors (res)
    (let ((user-id (car args))
          (get-notes (ignore-errors (< 0 (parse-integer (cl-ppcre:regex-replace-all "[^0-9]" (get-var req "get_notes") ""))))))
      (unless (string= (user-id req) user-id)
        (error 'insufficient-privileges :msg "You are trying to access another user's boards. For shame."))
      (alet* ((boards (get-user-boards user-id get-notes)))
        (send-json res boards)))))

(defroute (:post "/api/boards/users/([0-9a-f-]+)") (req res args)
  (catch-errors (res)
    (alet* ((user-id (car args))
            (board-data (post-var req "data")))
      (unless (string= (user-id req) user-id)
        (error 'insufficient-privileges :msg "You are trying to access another user's boards. For shame."))
      (alet ((board (add-board user-id board-data)))
        (send-json res board)))))

(defroute (:put "/api/boards/([0-9a-f-]+)") (req res args)
  (catch-errors (res)
    (alet* ((user-id (user-id req))
            (board-id (car args))
            (board-data (post-var req "data")))
      (alet ((board (edit-board user-id board-id board-data)))
        (send-json res board)))))

(defroute (:delete "/api/boards/([0-9a-f-]+)") (req res args)
  (catch-errors (res)
    (alet* ((board-id (car args))
            (user-id (user-id req))
            (nil (delete-board user-id board-id)))
      (send-json res t))))

(defroute (:put "/api/boards/([0-9a-f-]+)/permissions/persona/([0-9a-f-]+)") (req res args)
  (catch-errors (res)
    (alet* ((user-id (user-id req))
            (board-id (car args))
            (persona-id (cadr args))
            (permissions (post-var req "permissions"))
            (perms (set-board-persona-permissions user-id board-id persona-id permissions)))
      (send-json res perms))))

(defroute (:put "/api/boards/([0-9a-f-]+)/keys/persona/([0-9a-f-]+)") (req res args)
  (catch-errors (res)
    (alet* ((board-id (car args))
            (persona-id (cadr args))
            (challenge (post-var req "challenge"))
            (keydata (post-var req "keydata"))
            (success (board-add-persona-key board-id persona-id challenge keydata)))
      (send-json res success))))
