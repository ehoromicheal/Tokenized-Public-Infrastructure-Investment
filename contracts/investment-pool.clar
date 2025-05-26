;; Investment Pool Contract
;; Manages capital collection and token distribution for infrastructure projects

;; Constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-NOT-AUTHORIZED (err u200))
(define-constant ERR-POOL-NOT-FOUND (err u201))
(define-constant ERR-POOL-ALREADY-EXISTS (err u202))
(define-constant ERR-INSUFFICIENT-FUNDS (err u203))
(define-constant ERR-POOL-CLOSED (err u204))
(define-constant ERR-MINIMUM-NOT-MET (err u205))

;; Data Variables
(define-data-var next-pool-id uint u1)

;; Data Maps
(define-map investment-pools
  { pool-id: uint }
  {
    project-id: uint,
    target-amount: uint,
    raised-amount: uint,
    minimum-investment: uint,
    maximum-investment: uint,
    status: (string-ascii 20),
    created-at: uint,
    deadline: uint,
    total-tokens: uint
  }
)

(define-map investor-tokens
  { pool-id: uint, investor: principal }
  { tokens: uint, investment-amount: uint }
)

(define-map pool-balances
  { pool-id: uint }
  { balance: uint }
)

;; Public Functions

;; Create a new investment pool for an approved project
(define-public (create-pool (project-id uint) (target-amount uint) (minimum-investment uint) (maximum-investment uint) (duration uint))
  (let ((pool-id (var-get next-pool-id)))
    ;; Verify project is approved (would check with verification contract)
    (map-set investment-pools
      { pool-id: pool-id }
      {
        project-id: project-id,
        target-amount: target-amount,
        raised-amount: u0,
        minimum-investment: minimum-investment,
        maximum-investment: maximum-investment,
        status: "active",
        created-at: block-height,
        deadline: (+ block-height duration),
        total-tokens: u0
      }
    )
    (map-set pool-balances { pool-id: pool-id } { balance: u0 })
    (var-set next-pool-id (+ pool-id u1))
    (ok pool-id)
  )
)

;; Invest in a pool
(define-public (invest (pool-id uint) (amount uint))
  (let (
    (pool (unwrap! (map-get? investment-pools { pool-id: pool-id }) ERR-POOL-NOT-FOUND))
    (current-balance (default-to { balance: u0 } (map-get? pool-balances { pool-id: pool-id })))
    (current-tokens (default-to { tokens: u0, investment-amount: u0 } (map-get? investor-tokens { pool-id: pool-id, investor: tx-sender })))
  )
    (asserts! (is-eq (get status pool) "active") ERR-POOL-CLOSED)
    (asserts! (>= amount (get minimum-investment pool)) ERR-MINIMUM-NOT-MET)
    (asserts! (<= (+ block-height u0) (get deadline pool)) ERR-POOL-CLOSED)

    ;; Calculate tokens (1:1 ratio for simplicity)
    (let ((new-tokens amount))
      ;; Update pool
      (map-set investment-pools
        { pool-id: pool-id }
        (merge pool {
          raised-amount: (+ (get raised-amount pool) amount),
          total-tokens: (+ (get total-tokens pool) new-tokens)
        })
      )

      ;; Update investor tokens
      (map-set investor-tokens
        { pool-id: pool-id, investor: tx-sender }
        {
          tokens: (+ (get tokens current-tokens) new-tokens),
          investment-amount: (+ (get investment-amount current-tokens) amount)
        }
      )

      ;; Update pool balance
      (map-set pool-balances
        { pool-id: pool-id }
        { balance: (+ (get balance current-balance) amount) }
      )

      (ok new-tokens)
    )
  )
)

;; Close pool and finalize funding
(define-public (close-pool (pool-id uint))
  (let ((pool (unwrap! (map-get? investment-pools { pool-id: pool-id }) ERR-POOL-NOT-FOUND)))
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (asserts! (is-eq (get status pool) "active") ERR-POOL-CLOSED)

    (map-set investment-pools
      { pool-id: pool-id }
      (merge pool { status: "closed" })
    )
    (ok true)
  )
)

;; Read-only Functions

;; Get pool details
(define-read-only (get-pool (pool-id uint))
  (map-get? investment-pools { pool-id: pool-id })
)

;; Get investor tokens
(define-read-only (get-investor-tokens (pool-id uint) (investor principal))
  (map-get? investor-tokens { pool-id: pool-id, investor: investor })
)

;; Get pool balance
(define-read-only (get-pool-balance (pool-id uint))
  (map-get? pool-balances { pool-id: pool-id })
)

;; Get next pool ID
(define-read-only (get-next-pool-id)
  (var-get next-pool-id)
)
