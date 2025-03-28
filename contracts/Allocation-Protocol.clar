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

