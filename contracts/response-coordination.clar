;; Response Coordination Contract
;; Manages quantum security responses and incident coordination

(define-constant contract-owner tx-sender)
(define-constant err-unauthorized (err u500))
(define-constant err-incident-not-found (err u501))
(define-constant err-response-not-found (err u502))
(define-constant err-invalid-priority (err u503))
(define-constant err-invalid-status (err u504))

;; Priority levels
(define-constant priority-low u1)
(define-constant priority-medium u2)
(define-constant priority-high u3)
(define-constant priority-critical u4)

;; Incident status
(define-constant status-open u1)
(define-constant status-investigating u2)
(define-constant status-responding u3)
(define-constant status-resolved u4)
(define-constant status-closed u5)

;; Response types
(define-constant response-automated u1)
(define-constant response-manual u2)
(define-constant response-escalated u3)

;; Data structures
(define-map security-incidents
  { incident-id: uint }
  {
    reporter-id: principal,
    threat-id: (optional uint),
    incident-type: (string-ascii 32),
    priority: uint,
    status: uint,
    affected-systems: (string-ascii 256),
    description: (string-ascii 512),
    created-at: uint,
    updated-at: uint
  }
)

(define-map response-actions
  { response-id: uint }
  {
    incident-id: uint,
    responder-id: principal,
    action-type: (string-ascii 64),
    response-method: uint,
    action-description: (string-ascii 256),
    executed-at: uint,
    success: bool,
    notes: (string-ascii 256)
  }
)

(define-map response-teams
  { team-id: uint }
  {
    team-name: (string-ascii 64),
    lead-responder: principal,
    specialization: (string-ascii 64),
    active-incidents: uint,
    response-time-avg: uint,
    success-rate: uint
  }
)

(define-map incident-timeline
  { incident-id: uint, event-id: uint }
  {
    event-type: (string-ascii 32),
    event-description: (string-ascii 128),
    actor-id: principal,
    timestamp: uint
  }
)

(define-data-var next-incident-id uint u1)
(define-data-var next-response-id uint u1)
(define-data-var next-team-id uint u1)

;; Create a security incident
(define-public (create-incident
  (threat-id (optional uint))
  (incident-type (string-ascii 32))
  (priority uint)
  (affected-systems (string-ascii 256))
  (description (string-ascii 512))
)
  (let ((incident-id (var-get next-incident-id)))
    (asserts! (<= priority priority-critical) err-invalid-priority)
    (asserts! (>= priority priority-low) err-invalid-priority)
    (map-set security-incidents
      { incident-id: incident-id }
      {
        reporter-id: tx-sender,
        threat-id: threat-id,
        incident-type: incident-type,
        priority: priority,
        status: status-open,
        affected-systems: affected-systems,
        description: description,
        created-at: block-height,
        updated-at: block-height
      }
    )
    ;; Log incident creation
    (log-incident-event incident-id u0 "incident-created" "Security incident reported")
    (var-set next-incident-id (+ incident-id u1))
    (ok incident-id)
  )
)

;; Execute response action
(define-public (execute-response
  (incident-id uint)
  (action-type (string-ascii 64))
  (response-method uint)
  (action-description (string-ascii 256))
  (success bool)
  (notes (string-ascii 256))
)
  (let (
    (response-id (var-get next-response-id))
    (incident (unwrap! (map-get? security-incidents { incident-id: incident-id }) err-incident-not-found))
  )
    (map-set response-actions
      { response-id: response-id }
      {
        incident-id: incident-id,
        responder-id: tx-sender,
        action-type: action-type,
        response-method: response-method,
        action-description: action-description,
        executed-at: block-height,
        success: success,
        notes: notes
      }
    )
    ;; Update incident status if not already responding
    (if (is-eq (get status incident) status-open)
      (map-set security-incidents
        { incident-id: incident-id }
        (merge incident
          {
            status: status-responding,
            updated-at: block-height
          }
        )
      )
      true
    )
    ;; Log response action
    (log-incident-event incident-id response-id "response-executed" action-type)
    (var-set next-response-id (+ response-id u1))
    (ok response-id)
  )
)

;; Update incident status
(define-public (update-incident-status (incident-id uint) (new-status uint))
  (let ((incident (unwrap! (map-get? security-incidents { incident-id: incident-id }) err-incident-not-found)))
    (asserts! (<= new-status status-closed) err-invalid-status)
    (asserts! (>= new-status status-open) err-invalid-status)
    (map-set security-incidents
      { incident-id: incident-id }
      (merge incident
        {
          status: new-status,
          updated-at: block-height
        }
      )
    )
    ;; Log status change
    (log-incident-event incident-id u0 "status-updated" "Incident status changed")
    (ok true)
  )
)

;; Register response team
(define-public (register-response-team
  (team-name (string-ascii 64))
  (specialization (string-ascii 64))
)
  (let ((team-id (var-get next-team-id)))
    (map-set response-teams
      { team-id: team-id }
      {
        team-name: team-name,
        lead-responder: tx-sender,
        specialization: specialization,
        active-incidents: u0,
        response-time-avg: u0,
        success-rate: u100
      }
    )
    (var-set next-team-id (+ team-id u1))
    (ok team-id)
  )
)

;; Helper function to log incident events
(define-private (log-incident-event
  (incident-id uint)
  (event-id uint)
  (event-type (string-ascii 32))
  (event-description (string-ascii 128))
)
  (map-set incident-timeline
    { incident-id: incident-id, event-id: event-id }
    {
      event-type: event-type,
      event-description: event-description,
      actor-id: tx-sender,
      timestamp: block-height
    }
  )
)

;; Read-only functions
(define-read-only (get-incident (incident-id uint))
  (map-get? security-incidents { incident-id: incident-id })
)

(define-read-only (get-response-action (response-id uint))
  (map-get? response-actions { response-id: response-id })
)

(define-read-only (get-response-team (team-id uint))
  (map-get? response-teams { team-id: team-id })
)

(define-read-only (get-incident-event (incident-id uint) (event-id uint))
  (map-get? incident-timeline { incident-id: incident-id, event-id: event-id })
)

(define-read-only (get-incidents-by-priority (priority uint))
  ;; In a real implementation, this would filter incidents by priority
  ;; For simplicity, we return the next incident ID
  (var-get next-incident-id)
)

(define-read-only (get-next-incident-id)
  (var-get next-incident-id)
)
