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

