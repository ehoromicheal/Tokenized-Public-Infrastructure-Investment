;; Construction Tracking Contract
;; Monitors project progress and milestone completion

;; Constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-NOT-AUTHORIZED (err u300))
(define-constant ERR-PROJECT-NOT-FOUND (err u301))
(define-constant ERR-MILESTONE-NOT-FOUND (err u302))
(define-constant ERR-MILESTONE-ALREADY-COMPLETED (err u303))
(define-constant ERR-INVALID-PROGRESS (err u304))

;; Data Variables
(define-data-var next-milestone-id uint u1)

;; Data Maps
(define-map construction-projects
  { project-id: uint }
  {
    pool-id: uint,
    contractor: principal,
    start-date: uint,
    estimated-completion: uint,
    actual-completion: (optional uint),
    total-milestones: uint,
    completed-milestones: uint,
    status: (string-ascii 20),
    total-budget: uint,
    spent-budget: uint
  }
)

(define-map milestones
  { milestone-id: uint }
  {
    project-id: uint,
    title: (string-ascii 100),
    description: (string-ascii 300),
    target-date: uint,
    completion-date: (optional uint),
    budget-allocation: uint,
    status: (string-ascii 20),
    verifier: (optional principal)
  }
)

(define-map authorized-contractors principal bool)

;; Public Functions

;; Start construction tracking for a project
(define-public (start-construction (project-id uint) (pool-id uint) (contractor principal) (estimated-completion uint) (total-budget uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)

    (map-set construction-projects
      { project-id: project-id }
      {
        pool-id: pool-id,
        contractor: contractor,
        start-date: block-height,
        estimated-completion: estimated-completion,
        actual-completion: none,
        total-milestones: u0,
        completed-milestones: u0,
        status: "in-progress",
        total-budget: total-budget,
        spent-budget: u0
      }
    )

    ;; Authorize contractor
    (map-set authorized-contractors contractor true)
    (ok true)
  )
)

;; Add a milestone to a project
(define-public (add-milestone (project-id uint) (title (string-ascii 100)) (description (string-ascii 300)) (target-date uint) (budget-allocation uint))
  (let (
    (milestone-id (var-get next-milestone-id))
    (project (unwrap! (map-get? construction-projects { project-id: project-id }) ERR-PROJECT-NOT-FOUND))
  )
    (asserts! (or (is-eq tx-sender CONTRACT-OWNER) (is-eq tx-sender (get contractor project))) ERR-NOT-AUTHORIZED)

    (map-set milestones
      { milestone-id: milestone-id }
      {
        project-id: project-id,
        title: title,
        description: description,
        target-date: target-date,
        completion-date: none,
        budget-allocation: budget-allocation,
        status: "pending",
        verifier: none
      }
    )

    ;; Update project milestone count
    (map-set construction-projects
      { project-id: project-id }
      (merge project { total-milestones: (+ (get total-milestones project) u1) })
    )

    (var-set next-milestone-id (+ milestone-id u1))
    (ok milestone-id)
  )
)

;; Complete a milestone
(define-public (complete-milestone (milestone-id uint))
  (let (
    (milestone (unwrap! (map-get? milestones { milestone-id: milestone-id }) ERR-MILESTONE-NOT-FOUND))
    (project (unwrap! (map-get? construction-projects { project-id: (get project-id milestone) }) ERR-PROJECT-NOT-FOUND))
  )
    (asserts! (is-eq tx-sender (get contractor project)) ERR-NOT-AUTHORIZED)
    (asserts! (is-eq (get status milestone) "pending") ERR-MILESTONE-ALREADY-COMPLETED)

    ;; Update milestone
    (map-set milestones
      { milestone-id: milestone-id }
      (merge milestone {
        completion-date: (some block-height),
        status: "completed",
        verifier: (some tx-sender)
      })
    )

    ;; Update project
    (map-set construction-projects
      { project-id: (get project-id milestone) }
      (merge project {
        completed-milestones: (+ (get completed-milestones project) u1),
        spent-budget: (+ (get spent-budget project) (get budget-allocation milestone))
      })
    )

    (ok true)
  )
)

;; Complete entire project
(define-public (complete-project (project-id uint))
  (let ((project (unwrap! (map-get? construction-projects { project-id: project-id }) ERR-PROJECT-NOT-FOUND)))
    (asserts! (is-eq tx-sender (get contractor project)) ERR-NOT-AUTHORIZED)
    (asserts! (is-eq (get status project) "in-progress") ERR-INVALID-PROGRESS)

    (map-set construction-projects
      { project-id: project-id }
      (merge project {
        status: "completed",
        actual-completion: (some block-height)
      })
    )
    (ok true)
  )
)

;; Read-only Functions

;; Get construction project details
(define-read-only (get-construction-project (project-id uint))
  (map-get? construction-projects { project-id: project-id })
)

;; Get milestone details
(define-read-only (get-milestone (milestone-id uint))
  (map-get? milestones { milestone-id: milestone-id })
)

;; Calculate project progress percentage
(define-read-only (get-project-progress (project-id uint))
  (match (map-get? construction-projects { project-id: project-id })
    project (if (> (get total-milestones project) u0)
              (/ (* (get completed-milestones project) u100) (get total-milestones project))
              u0)
    u0
  )
)

;; Check if contractor is authorized
(define-read-only (is-authorized-contractor (contractor principal))
  (default-to false (map-get? authorized-contractors contractor))
)
