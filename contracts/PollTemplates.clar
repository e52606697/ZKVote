;; Poll Templates Contract for ZKVote
;; Enables creation and management of reusable poll templates

;; Error constants
(define-constant ERR_NOT_AUTHORIZED (err u200))
(define-constant ERR_TEMPLATE_NOT_FOUND (err u201))
(define-constant ERR_TEMPLATE_NAME_EXISTS (err u202))
(define-constant ERR_INVALID_TEMPLATE_NAME (err u203))
(define-constant ERR_INVALID_OPTIONS (err u204))
(define-constant ERR_INVALID_DURATION (err u205))
(define-constant ERR_TEMPLATE_LOCKED (err u206))
(define-constant ERR_INSUFFICIENT_REPUTATION (err u207))

;; Contract owner and constants
(define-constant CONTRACT_OWNER tx-sender)
(define-constant MIN_TEMPLATE_REPUTATION u150)
(define-constant MAX_TEMPLATE_DURATION u10080) ;; ~1 week in blocks

;; Data variables
(define-data-var template-counter uint u0)
(define-data-var template-creation-fee uint u5000)

;; Template registry mapping
(define-map poll-templates
  { template-id: uint }
  {
    name: (string-ascii 50),
    description: (string-ascii 200),
    creator: principal,
    default-options: (list 10 (string-ascii 50)),
    default-duration: uint,
    category: (string-ascii 30),
    is-public: bool,
    is-locked: bool,
    creation-block: uint,
    usage-count: uint,
    minimum-stake: uint
  }
)

;; Template usage tracking
(define-map template-usage
  { template-id: uint, user: principal }
  {
    polls-created: uint,
    last-used-block: uint,
    total-votes-generated: uint
  }
)

;; Template names registry for uniqueness
(define-map template-names
  { name: (string-ascii 50) }
  { template-id: uint, creator: principal }
)

;; Template categories for organization
(define-map template-categories
  { category: (string-ascii 30) }
  { template-count: uint, is-active: bool }
)

;; Create a new poll template
(define-public (create-template 
  (name (string-ascii 50))
  (description (string-ascii 200))
  (default-options (list 10 (string-ascii 50)))
  (default-duration uint)
  (category (string-ascii 30))
  (is-public bool)
  (minimum-stake uint))
  
  (let
    (
      (template-id (+ (var-get template-counter) u1))
      (existing-name (map-get? template-names { name: name }))
      (creator-reputation (get-user-reputation tx-sender))
      (creation-fee (var-get template-creation-fee))
    )
    ;; Validations
    (asserts! (> (len name) u0) ERR_INVALID_TEMPLATE_NAME)
    (asserts! (is-none existing-name) ERR_TEMPLATE_NAME_EXISTS)
    (asserts! (> (len default-options) u1) ERR_INVALID_OPTIONS)
    (asserts! (<= (len default-options) u10) ERR_INVALID_OPTIONS)
    (asserts! (and (> default-duration u0) (<= default-duration MAX_TEMPLATE_DURATION)) ERR_INVALID_DURATION)
    (asserts! (>= creator-reputation MIN_TEMPLATE_REPUTATION) ERR_INSUFFICIENT_REPUTATION)
    
    ;; Transfer creation fee
    (try! (stx-transfer? creation-fee tx-sender (as-contract tx-sender)))
    
    ;; Create template
    (map-set poll-templates
      { template-id: template-id }
      {
        name: name,
        description: description,
        creator: tx-sender,
        default-options: default-options,
        default-duration: default-duration,
        category: category,
        is-public: is-public,
        is-locked: false,
        creation-block: stacks-block-height,
        usage-count: u0,
        minimum-stake: minimum-stake
      }
    )
    
    ;; Register template name
    (map-set template-names
      { name: name }
      { template-id: template-id, creator: tx-sender }
    )
    
    ;; Update category counter
    (update-category-count category)
    
    ;; Update template counter
    (var-set template-counter template-id)
    
    (ok template-id)
  )
)

;; Create poll from template
(define-public (create-poll-from-template 
  (template-id uint)
  (title (string-ascii 100))
  (custom-description (optional (string-ascii 500))))
  
  (let
    (
      (template-data (unwrap! (map-get? poll-templates { template-id: template-id }) ERR_TEMPLATE_NOT_FOUND))
      (user-reputation (get-user-reputation tx-sender))
      (description (default-to (get description template-data) custom-description))
    )
    ;; Validations
    (asserts! (or (get is-public template-data) (is-eq tx-sender (get creator template-data))) ERR_NOT_AUTHORIZED)
    (asserts! (>= user-reputation (get minimum-stake template-data)) ERR_INSUFFICIENT_REPUTATION)
    (asserts! (> (len title) u0) ERR_INVALID_TEMPLATE_NAME)
    
    ;; Create poll using template data
    (let
      (
        (poll-result (contract-call? .ZKVote create-poll
          title
          description
          (get default-options template-data)
          (get default-duration template-data)))
      )
      (if (is-ok poll-result)
        (begin
          ;; Update template usage count
          (map-set poll-templates
            { template-id: template-id }
            (merge template-data { usage-count: (+ (get usage-count template-data) u1) })
          )
          
          ;; Track user's template usage
          (update-user-template-usage template-id tx-sender)
          
          poll-result
        )
        poll-result
      )
    )
  )
)

;; Update template (creator only)
(define-public (update-template
  (template-id uint)
  (new-description (optional (string-ascii 200)))
  (new-default-duration (optional uint))
  (new-is-public (optional bool)))
  
  (let
    (
      (template-data (unwrap! (map-get? poll-templates { template-id: template-id }) ERR_TEMPLATE_NOT_FOUND))
    )
    (asserts! (is-eq tx-sender (get creator template-data)) ERR_NOT_AUTHORIZED)
    (asserts! (not (get is-locked template-data)) ERR_TEMPLATE_LOCKED)
    
    (map-set poll-templates
      { template-id: template-id }
      (merge template-data {
        description: (default-to (get description template-data) new-description),
        default-duration: (default-to (get default-duration template-data) new-default-duration),
        is-public: (default-to (get is-public template-data) new-is-public)
      })
    )
    
    (ok true)
  )
)

;; Lock template to prevent further modifications
(define-public (lock-template (template-id uint))
  (let
    (
      (template-data (unwrap! (map-get? poll-templates { template-id: template-id }) ERR_TEMPLATE_NOT_FOUND))
    )
    (asserts! (is-eq tx-sender (get creator template-data)) ERR_NOT_AUTHORIZED)
    (asserts! (not (get is-locked template-data)) ERR_TEMPLATE_LOCKED)
    
    (map-set poll-templates
      { template-id: template-id }
      (merge template-data { is-locked: true })
    )
    
    (ok true)
  )
)

;; Delete template (creator only, if unused)
(define-public (delete-template (template-id uint))
  (let
    (
      (template-data (unwrap! (map-get? poll-templates { template-id: template-id }) ERR_TEMPLATE_NOT_FOUND))
    )
    (asserts! (is-eq tx-sender (get creator template-data)) ERR_NOT_AUTHORIZED)
    (asserts! (is-eq (get usage-count template-data) u0) ERR_TEMPLATE_LOCKED)
    
    ;; Remove from templates map
    (map-delete poll-templates { template-id: template-id })
    
    ;; Remove from names registry
    (map-delete template-names { name: (get name template-data) })
    
    (ok true)
  )
)

;; Helper functions
(define-private (update-category-count (category (string-ascii 30)))
  (let
    (
      (category-data (default-to { template-count: u0, is-active: true } 
                      (map-get? template-categories { category: category })))
    )
    (map-set template-categories
      { category: category }
      (merge category-data { template-count: (+ (get template-count category-data) u1) })
    )
    true
  )
)

(define-private (update-user-template-usage (template-id uint) (user principal))
  (let
    (
      (usage-data (default-to { polls-created: u0, last-used-block: u0, total-votes-generated: u0 }
                   (map-get? template-usage { template-id: template-id, user: user })))
    )
    (map-set template-usage
      { template-id: template-id, user: user }
      (merge usage-data {
        polls-created: (+ (get polls-created usage-data) u1),
        last-used-block: stacks-block-height
      })
    )
    true
  )
)

(define-private (get-user-reputation (user principal))
  (match (contract-call? .ZKVote get-voter-stake user)
    stake-data (get reputation-score stake-data)
    u0
  )
)

;; Read-only functions
(define-read-only (get-template (template-id uint))
  (map-get? poll-templates { template-id: template-id })
)

(define-read-only (get-template-by-name (name (string-ascii 50)))
  (match (map-get? template-names { name: name })
    name-data (map-get? poll-templates { template-id: (get template-id name-data) })
    none
  )
)

(define-read-only (get-template-usage (template-id uint) (user principal))
  (map-get? template-usage { template-id: template-id, user: user })
)

(define-read-only (get-category-info (category (string-ascii 30)))
  (map-get? template-categories { category: category })
)

(define-read-only (get-template-count)
  (var-get template-counter)
)

(define-read-only (get-template-creation-fee)
  (var-get template-creation-fee)
)

(define-read-only (is-template-available (template-id uint) (user principal))
  (match (map-get? poll-templates { template-id: template-id })
    template-data
    (or 
      (get is-public template-data)
      (is-eq user (get creator template-data))
    )
    false
  )
)

;; Admin functions
(define-public (set-template-creation-fee (new-fee uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_NOT_AUTHORIZED)
    (var-set template-creation-fee new-fee)
    (ok new-fee)
  )
)

(define-public (set-min-template-reputation (new-min uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_NOT_AUTHORIZED)
    (ok new-min)
  )
)
