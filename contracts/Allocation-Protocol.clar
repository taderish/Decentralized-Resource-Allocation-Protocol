;; Decentralized Resource Allocation Protocol
;; A comprehensive blockchain-based resource distribution mechanism

;; Core system configurations
(define-constant PROTOCOL_ADMIN tx-sender)
(define-constant ERR_UNAUTHORIZED (err u100))
(define-constant ERR_ALLOCATION_NOT_FOUND (err u101))
(define-constant ERR_FUNDS_RELEASED (err u102))
(define-constant ERR_TRANSFER_FAILED (err u103))
(define-constant ERR_INVALID_ALLOCATION_ID (err u104))
(define-constant ERR_INVALID_AMOUNT (err u105))
(define-constant ERR_INVALID_MILESTONE_CONFIG (err u106))
(define-constant ERR_ALLOCATION_EXPIRED (err u107))
(define-constant ALLOCATION_DURATION u1008) 

;; Resource allocation tracking
(define-map ImpactAllocations
  { allocation-id: uint }
  {
    initiator: principal,
    recipient: principal,
    total-resource: uint,
    status: (string-ascii 10),
    creation-block: uint,
    expiration-block: uint,
    milestone-stages: (list 5 uint),
    approved-stage-count: uint
  }
)

(define-data-var latest-allocation-id uint u0)

;; Primary allocation initialization
(define-public (launch-impact-allocation (recipient principal) (resource-amount uint) (milestone-stages (list 5 uint)))
  (let
    (
      (allocation-id (+ (var-get latest-allocation-id) u1))
      (expiration-block (+ block-height ALLOCATION_DURATION))
    )
    (asserts! (> resource-amount u0) ERR_INVALID_AMOUNT)
    (asserts! (validate-recipient recipient) ERR_INVALID_MILESTONE_CONFIG)
    (asserts! (> (len milestone-stages) u0) ERR_INVALID_MILESTONE_CONFIG)

    (match (stx-transfer? resource-amount tx-sender (as-contract tx-sender))
      success
        (begin
          (map-set ImpactAllocations
            { allocation-id: allocation-id }
            {
              initiator: tx-sender,
              recipient: recipient,
              total-resource: resource-amount,
              status: "pending",
              creation-block: block-height,
              expiration-block: expiration-block,
              milestone-stages: milestone-stages,
              approved-stage-count: u0
            }
          )
          (var-set latest-allocation-id allocation-id)
          (ok allocation-id)
        )
      error ERR_TRANSFER_FAILED
    )
  )
)

(define-private (validate-recipient (recipient principal))
  (not (is-eq recipient tx-sender))
)

(define-private (is-valid-allocation-id (allocation-id uint))
  (<= allocation-id (var-get latest-allocation-id))
)

;; Stage validation and resource release
(define-public (validate-allocation-stage (allocation-id uint))
  (begin
    (asserts! (is-valid-allocation-id allocation-id) ERR_INVALID_ALLOCATION_ID)
    (let
      (
        (allocation (unwrap! (map-get? ImpactAllocations { allocation-id: allocation-id }) ERR_ALLOCATION_NOT_FOUND))
        (milestone-stages (get milestone-stages allocation))
        (approved-count (get approved-stage-count allocation))
        (recipient (get recipient allocation))
        (total-resource (get total-resource allocation))
        (stage-resource-amount (/ total-resource (len milestone-stages)))
      )
      (asserts! (< approved-count (len milestone-stages)) ERR_FUNDS_RELEASED)
      (asserts! (is-eq tx-sender PROTOCOL_ADMIN) ERR_UNAUTHORIZED)

      (match (stx-transfer? stage-resource-amount (as-contract tx-sender) recipient)
        success
          (begin
            (map-set ImpactAllocations
              { allocation-id: allocation-id }
              (merge allocation { approved-stage-count: (+ approved-count u1) })
            )
            (ok true)
          )
        error ERR_TRANSFER_FAILED
      )
    )
  )
)

;; Initiator refund mechanism
(define-public (refund-initiator (allocation-id uint))
  (begin
    (asserts! (is-valid-allocation-id allocation-id) ERR_INVALID_ALLOCATION_ID)
    (let
      (
        (allocation (unwrap! (map-get? ImpactAllocations { allocation-id: allocation-id }) ERR_ALLOCATION_NOT_FOUND))
        (initiator (get initiator allocation))
        (resource-amount (get total-resource allocation))
      )
      (asserts! (is-eq tx-sender PROTOCOL_ADMIN) ERR_UNAUTHORIZED)
      (asserts! (> block-height (get expiration-block allocation)) ERR_ALLOCATION_EXPIRED)

      (match (stx-transfer? resource-amount (as-contract tx-sender) initiator)
        success
          (begin
            (map-set ImpactAllocations
              { allocation-id: allocation-id }
              (merge allocation { status: "refunded" })
            )
            (ok true)
          )
        error ERR_TRANSFER_FAILED
      )
    )
  )
)

;; Allocation termination by initiator
(define-public (terminate-allocation (allocation-id uint))
  (begin
    (asserts! (is-valid-allocation-id allocation-id) ERR_INVALID_ALLOCATION_ID)
    (let
      (
        (allocation (unwrap! (map-get? ImpactAllocations { allocation-id: allocation-id }) ERR_ALLOCATION_NOT_FOUND))
        (initiator (get initiator allocation))
        (resource-amount (get total-resource allocation))
        (approved-count (get approved-stage-count allocation))
        (remaining-resource (- resource-amount (* (/ resource-amount (len (get milestone-stages allocation))) approved-count)))
      )
      (asserts! (is-eq tx-sender initiator) ERR_UNAUTHORIZED)
      (asserts! (< block-height (get expiration-block allocation)) ERR_ALLOCATION_EXPIRED)
      (asserts! (is-eq (get status allocation) "pending") ERR_FUNDS_RELEASED)

      (match (stx-transfer? remaining-resource (as-contract tx-sender) initiator)
        success
          (begin
            (map-set ImpactAllocations
              { allocation-id: allocation-id }
              (merge allocation { status: "terminated" })
            )
            (ok true)
          )
        error ERR_TRANSFER_FAILED
      )
    )
  )
)

;; Rate limiting system
(define-constant ERR_RATE_LIMIT_EXCEEDED (err u213))
(define-constant RATE_LIMIT_WINDOW u144)
(define-constant MAX_ALLOCATIONS_PER_WINDOW u5)

(define-map InitiatorActivityTracker
  { initiator: principal }
  {
    last-allocation-block: uint,
    allocations-in-window: uint
  }
)

;; Donation Challenge Mechanism
(define-constant ERR_CHALLENGE_ALREADY_EXISTS (err u236))
(define-constant ERR_CHALLENGE_PERIOD_EXPIRED (err u237))
(define-constant CHALLENGE_PERIOD_BLOCKS u1008)
(define-constant CHALLENGE_BOND u1000000)

(define-map AllocationChallenges
  { allocation-id: uint }
  {
    challenger: principal,
    challenge-reason: (string-ascii 200),
    challenge-bond: uint,
    resolved: bool,
    valid-challenge: bool,
    challenge-block: uint
  }
)

(define-public (submit-allocation-challenge 
                (allocation-id uint)
                (challenge-reason (string-ascii 200)))
  (begin
    (asserts! (is-valid-allocation-id allocation-id) ERR_INVALID_ALLOCATION_ID)
    (let
      (
        (allocation (unwrap! (map-get? ImpactAllocations { allocation-id: allocation-id }) ERR_ALLOCATION_NOT_FOUND))
      )
      (match (map-get? AllocationChallenges { allocation-id: allocation-id })
        existing-challenge (asserts! false ERR_CHALLENGE_ALREADY_EXISTS)
        true
      )

      (match (stx-transfer? CHALLENGE_BOND tx-sender (as-contract tx-sender))
        success
            (ok true)
        error ERR_TRANSFER_FAILED
      )
    )
  )
)

(define-public (resolve-allocation-challenge (allocation-id uint) (is-valid bool))
  (begin
    (asserts! (is-eq tx-sender PROTOCOL_ADMIN) ERR_UNAUTHORIZED)
    (let
      (
        (challenge (unwrap! 
          (map-get? AllocationChallenges { allocation-id: allocation-id }) 
          ERR_ALLOCATION_NOT_FOUND))
        (challenge-block (get challenge-block challenge))
      )
      (asserts! (not (get resolved challenge)) ERR_UNAUTHORIZED)
      (asserts! (< (- block-height challenge-block) CHALLENGE_PERIOD_BLOCKS) ERR_CHALLENGE_PERIOD_EXPIRED)

      (if is-valid
        (match (stx-transfer? (get challenge-bond challenge) (as-contract tx-sender) (get challenger challenge))
          success (ok true)
          error ERR_TRANSFER_FAILED
        )
        (match (stx-transfer? (get challenge-bond challenge) (as-contract tx-sender) PROTOCOL_ADMIN)
          success (ok true)
          error ERR_TRANSFER_FAILED
        )
      )
    )
  )
)

(define-private (get-recipient-percentage (recipient { target: principal, allocation-percentage: uint }))
  (get allocation-percentage recipient)
)

;; Admin control interface
(define-data-var protocol-paused bool false)

(define-public (set-protocol-pause-state (new-state bool))
  (begin
    (asserts! (is-eq tx-sender PROTOCOL_ADMIN) ERR_UNAUTHORIZED)
    (ok new-state)
  )
)

;; Recipient whitelist management
(define-map ApprovedRecipients
  { recipient: principal }
  { approved: bool }
)

(define-read-only (is-recipient-approved (recipient principal))
  (default-to false (get approved (map-get? ApprovedRecipients { recipient: recipient })))
)

;; Allocation expiration extension
(define-constant ERR_ALREADY_EXPIRED (err u208))
(define-constant MAX_EXTENSION_BLOCKS u1008) ;; ~7 days extension window

(define-public (extend-allocation-expiration (allocation-id uint) (extension-blocks uint))
  (begin
    (asserts! (is-valid-allocation-id allocation-id) ERR_INVALID_ALLOCATION_ID)
    (asserts! (<= extension-blocks MAX_EXTENSION_BLOCKS) ERR_INVALID_AMOUNT)
    (let
      (
        (allocation (unwrap! (map-get? ImpactAllocations { allocation-id: allocation-id }) ERR_ALLOCATION_NOT_FOUND))
        (initiator (get initiator allocation))
        (current-expiry (get expiration-block allocation))
      )
      (asserts! (is-eq tx-sender initiator) ERR_UNAUTHORIZED)
      (asserts! (< block-height current-expiry) ERR_ALREADY_EXPIRED)
      (map-set ImpactAllocations
        { allocation-id: allocation-id }
        (merge allocation { expiration-block: (+ current-expiry extension-blocks) })
      )
      (ok true)
    )
  )
)

;; Resource amount augmentation
(define-public (increase-allocation-resource (allocation-id uint) (additional-resource uint))
  (begin
    (asserts! (is-valid-allocation-id allocation-id) ERR_INVALID_ALLOCATION_ID)
    (asserts! (> additional-resource u0) ERR_INVALID_AMOUNT)
    (let
      (
        (allocation (unwrap! (map-get? ImpactAllocations { allocation-id: allocation-id }) ERR_ALLOCATION_NOT_FOUND))
        (initiator (get initiator allocation))
        (current-resource (get total-resource allocation))
      )
      (asserts! (is-eq tx-sender initiator) ERR_UNAUTHORIZED)
      (asserts! (< block-height (get expiration-block allocation)) ERR_ALLOCATION_EXPIRED)
      (match (stx-transfer? additional-resource tx-sender (as-contract tx-sender))
        success
          (begin
            (map-set ImpactAllocations
              { allocation-id: allocation-id }
              (merge allocation { total-resource: (+ current-resource additional-resource) })
            )
            (ok true)
          )
        error ERR_TRANSFER_FAILED
      )
    )
  )
)


;; Emergency resource recovery
(define-constant ERR_EMERGENCY_NOT_APPROVED (err u209))
(define-map EmergencyRecoveryRequests
  { allocation-id: uint }
  { 
    admin-approved: bool,
    initiator-approved: bool,
    reason: (string-ascii 100)
  }
)

(define-public (emergency-resource-recovery (allocation-id uint) (reason (string-ascii 100)))
  (begin
    (asserts! (is-valid-allocation-id allocation-id) ERR_INVALID_ALLOCATION_ID)
    (let
      (
        (allocation (unwrap! (map-get? ImpactAllocations { allocation-id: allocation-id }) ERR_ALLOCATION_NOT_FOUND))
        (initiator (get initiator allocation))
        (resource-amount (get total-resource allocation))
        (approved-count (get approved-stage-count allocation))
        (remaining-resource (- resource-amount (* (/ resource-amount (len (get milestone-stages allocation))) approved-count)))
        (emergency-request (default-to 
                            { admin-approved: false, initiator-approved: false, reason: reason }
                            (map-get? EmergencyRecoveryRequests { allocation-id: allocation-id })))
      )
      (asserts! (or (is-eq tx-sender PROTOCOL_ADMIN) (is-eq tx-sender initiator)) ERR_UNAUTHORIZED)
      (asserts! (not (is-eq (get status allocation) "refunded")) ERR_FUNDS_RELEASED)
      (asserts! (not (is-eq (get status allocation) "recovered")) ERR_FUNDS_RELEASED)

      (if (is-eq tx-sender PROTOCOL_ADMIN)
        (map-set EmergencyRecoveryRequests
          { allocation-id: allocation-id }
          (merge emergency-request { admin-approved: true, reason: reason })
        )
        (map-set EmergencyRecoveryRequests
          { allocation-id: allocation-id }
          (merge emergency-request { initiator-approved: true, reason: reason })
        )
      )

      (let
        (
          (updated-request (unwrap! (map-get? EmergencyRecoveryRequests { allocation-id: allocation-id }) ERR_ALLOCATION_NOT_FOUND))
        )
        (if (and (get admin-approved updated-request) (get initiator-approved updated-request))
          (match (stx-transfer? remaining-resource (as-contract tx-sender) initiator)
            success
              (begin
                (map-set ImpactAllocations
                  { allocation-id: allocation-id }
                  (merge allocation { status: "recovered" })
                )
                (ok true)
              )
            error ERR_TRANSFER_FAILED
          )
          (ok false)
        )
      )
    )
  )
)

;; Milestone progress tracking
(define-constant ERR_PROGRESS_ALREADY_REPORTED (err u210))
(define-map MilestoneProgress
  { allocation-id: uint, milestone-index: uint }
  {
    progress-percentage: uint,
    details: (string-ascii 200),
    reported-at: uint,
    evidence-hash: (buff 32)
  }
)

(define-public (report-milestone-progress 
                (allocation-id uint) 
                (milestone-index uint) 
                (progress-percentage uint) 
                (details (string-ascii 200))
                (evidence-hash (buff 32)))
  (begin
    (asserts! (is-valid-allocation-id allocation-id) ERR_INVALID_ALLOCATION_ID)
    (asserts! (<= progress-percentage u100) ERR_INVALID_AMOUNT)
    (let
      (
        (allocation (unwrap! (map-get? ImpactAllocations { allocation-id: allocation-id }) ERR_ALLOCATION_NOT_FOUND))
        (milestone-stages (get milestone-stages allocation))
        (recipient (get recipient allocation))
      )
      (asserts! (is-eq tx-sender recipient) ERR_UNAUTHORIZED)
      (asserts! (< milestone-index (len milestone-stages)) ERR_INVALID_MILESTONE_CONFIG)
      (asserts! (not (is-eq (get status allocation) "refunded")) ERR_FUNDS_RELEASED)
      (asserts! (< block-height (get expiration-block allocation)) ERR_ALLOCATION_EXPIRED)

      (match (map-get? MilestoneProgress { allocation-id: allocation-id, milestone-index: milestone-index })
        prev-progress (asserts! (< (get progress-percentage prev-progress) u100) ERR_PROGRESS_ALREADY_REPORTED)
        true
      )
      (ok true)
    )
  )
)

(define-private (validate-stage-fold (allocation-id uint) (prev-result (response bool uint)))
  (begin
    (match prev-result
      success
        (match (validate-allocation-stage allocation-id)
          inner-success (ok true)
          inner-error (err inner-error)
        )
      error (err error)
    )
  )
)

;; Secure allocation initiation with recipient whitelist
(define-public (secure-launch-impact-allocation (recipient principal) (resource-amount uint) (milestone-stages (list 5 uint)))
  (begin
    (asserts! (not (var-get protocol-paused)) ERR_UNAUTHORIZED)
    (asserts! (is-recipient-approved recipient) ERR_UNAUTHORIZED)
    (asserts! (> resource-amount u0) ERR_INVALID_AMOUNT)
    (asserts! (validate-recipient recipient) ERR_INVALID_MILESTONE_CONFIG)
    (asserts! (> (len milestone-stages) u0) ERR_INVALID_MILESTONE_CONFIG)

    (let
      (
        (allocation-id (+ (var-get latest-allocation-id) u1))
        (expiration-block (+ block-height ALLOCATION_DURATION))
      )
      (match (stx-transfer? resource-amount tx-sender (as-contract tx-sender))
        success
          (begin
            (map-set ImpactAllocations
              { allocation-id: allocation-id }
              {
                initiator: tx-sender,
                recipient: recipient,
                total-resource: resource-amount,
                status: "pending",
                creation-block: block-height,
                expiration-block: expiration-block,
                milestone-stages: milestone-stages,
                approved-stage-count: u0
              }
            )
            (var-set latest-allocation-id allocation-id)
            (ok allocation-id)
          )
        error ERR_TRANSFER_FAILED
      )
    )
  )
)

;; Circuit breaker protection mechanism
(define-constant CIRCUIT_COOLDOWN u720) ;; ~5 days protection window
(define-constant ERR_CIRCUIT_ACTIVE (err u222))
(define-constant ERR_CIRCUIT_TRIGGER_COOLDOWN (err u223))

;; Multi-recipient resource distribution
(define-constant MAX_RECIPIENTS u5)
(define-constant ERR_TOO_MANY_RECIPIENTS (err u224))
(define-constant ERR_INVALID_DISTRIBUTION (err u225))

(define-map SplitResourceAllocations
  { split-allocation-id: uint }
  {
    initiator: principal,
    recipients: (list 5 { target: principal, allocation-percentage: uint }),
    total-resource: uint,
    creation-block: uint,
    status: (string-ascii 10)
  }
)

(define-data-var latest-split-allocation-id uint u0)

(define-public (create-split-resource-allocation (recipients (list 5 { target: principal, allocation-percentage: uint })) (resource-amount uint))
  (begin
    (asserts! (> resource-amount u0) ERR_INVALID_AMOUNT)
    (asserts! (> (len recipients) u0) ERR_INVALID_ALLOCATION_ID)
    (asserts! (<= (len recipients) MAX_RECIPIENTS) ERR_TOO_MANY_RECIPIENTS)

    (let
      (
        (total-percentage (fold + (map get-recipient-percentage recipients) u0))
      )
      (asserts! (is-eq total-percentage u100) ERR_INVALID_DISTRIBUTION)

      (match (stx-transfer? resource-amount tx-sender (as-contract tx-sender))
        success
          (let
            (
              (allocation-id (+ (var-get latest-split-allocation-id) u1))
            )
            (map-set SplitResourceAllocations
              { split-allocation-id: allocation-id }
              {
                initiator: tx-sender,
                recipients: recipients,
                total-resource: resource-amount,
                creation-block: block-height,
                status: "pending"
              }
            )
            (var-set latest-split-allocation-id allocation-id)
            (ok allocation-id)
          )
        error ERR_TRANSFER_FAILED
      )
    )
  )
)

(define-public (rate-limited-impact-allocation (recipient principal) (resource-amount uint) (milestone-stages (list 5 uint)))
  (let
    (
      (initiator-activity (default-to 
                        { last-allocation-block: u0, allocations-in-window: u0 }
                        (map-get? InitiatorActivityTracker { initiator: tx-sender })))
      (last-block (get last-allocation-block initiator-activity))
      (window-count (get allocations-in-window initiator-activity))
      (is-new-window (> (- block-height last-block) RATE_LIMIT_WINDOW))
      (updated-count (if is-new-window u1 (+ window-count u1)))
    )
    (asserts! (or is-new-window (< window-count MAX_ALLOCATIONS_PER_WINDOW)) ERR_RATE_LIMIT_EXCEEDED)

    (map-set InitiatorActivityTracker
      { initiator: tx-sender }
      {
        last-allocation-block: block-height,
        allocations-in-window: updated-count
      }
    )

    (secure-launch-impact-allocation recipient resource-amount milestone-stages)
  )
)

;; Fraud detection mechanism
(define-constant ERR_SUSPICIOUS_ACTIVITY (err u215))
(define-constant SUSPICIOUS_AMOUNT_THRESHOLD u1000000000)
(define-constant SUSPICIOUS_RATE_THRESHOLD u3)

(define-map SuspiciousAllocations
  { allocation-id: uint }
  { 
    reason: (string-ascii 20),
    flagged-by: principal,
    resolved: bool
  }
)

(define-public (flag-suspicious-allocation (allocation-id uint) (reason (string-ascii 20)))
  (begin
    (asserts! (is-valid-allocation-id allocation-id) ERR_INVALID_ALLOCATION_ID)

    (let
      (
        (allocation (unwrap! (map-get? ImpactAllocations { allocation-id: allocation-id }) ERR_ALLOCATION_NOT_FOUND))
        (recipient (get recipient allocation))
      )
      (asserts! (or (is-eq tx-sender PROTOCOL_ADMIN) (is-eq tx-sender recipient)) ERR_UNAUTHORIZED)

      (map-set ImpactAllocations
        { allocation-id: allocation-id }
        (merge allocation { status: "flagged" })
      )

      (ok true)
    )
  )
)






