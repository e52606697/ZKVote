(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_NOT_AUTHORIZED (err u100))
(define-constant ERR_POLL_NOT_FOUND (err u101))
(define-constant ERR_POLL_ENDED (err u102))
(define-constant ERR_ALREADY_VOTED (err u103))
(define-constant ERR_INVALID_OPTION (err u104))
(define-constant ERR_POLL_ACTIVE (err u105))
(define-constant ERR_INVALID_COMMITMENT (err u106))
(define-constant ERR_INVALID_NULLIFIER (err u107))
(define-constant ERR_NULLIFIER_USED (err u108))

(define-data-var poll-counter uint u0)

(define-map polls
  { poll-id: uint }
  {
    title: (string-ascii 100),
    description: (string-ascii 500),
    options: (list 10 (string-ascii 50)),
    creator: principal,
    end-block: uint,
    total-votes: uint,
    is-active: bool
  }
)

(define-map poll-results
  { poll-id: uint, option-index: uint }
  { vote-count: uint }
)

(define-map commitments
  { poll-id: uint, commitment-hash: (buff 32) }
  { stacks-block-height: uint, is-revealed: bool }
)

(define-map nullifiers
  { nullifier-hash: (buff 32) }
  { poll-id: uint, used: bool }
)

(define-map voter-commitments
  { voter: principal, poll-id: uint }
  { commitment-hash: (buff 32), has-voted: bool }
)

(define-map zk-proofs
  { poll-id: uint, proof-hash: (buff 32) }
  { nullifier: (buff 32), vote-option: uint, is-valid: bool }
)

(define-public (create-poll (title (string-ascii 100)) (description (string-ascii 500)) (options (list 10 (string-ascii 50))) (duration uint))
  (let
    (
      (poll-id (+ (var-get poll-counter) u1))
      (end-block (+ stacks-block-height duration))
    )
    (map-set polls
      { poll-id: poll-id }
      {
        title: title,
        description: description,
        options: options,
        creator: tx-sender,
        end-block: end-block,
        total-votes: u0,
        is-active: true
      }
    )
    (var-set poll-counter poll-id)
    (ok poll-id)
  )
)

(define-public (commit-vote (poll-id uint) (commitment-hash (buff 32)))
  (let
    (
      (poll-data (unwrap! (map-get? polls { poll-id: poll-id }) ERR_POLL_NOT_FOUND))
      (existing-commitment (map-get? voter-commitments { voter: tx-sender, poll-id: poll-id }))
    )
    (asserts! (get is-active poll-data) ERR_POLL_ENDED)
    (asserts! (< stacks-block-height (get end-block poll-data)) ERR_POLL_ENDED)
    (asserts! (is-none existing-commitment) ERR_ALREADY_VOTED)
    (asserts! (> (len commitment-hash) u0) ERR_INVALID_COMMITMENT)
    
    (map-set commitments
      { poll-id: poll-id, commitment-hash: commitment-hash }
      { stacks-block-height: stacks-block-height, is-revealed: false }
    )
    
    (map-set voter-commitments
      { voter: tx-sender, poll-id: poll-id }
      { commitment-hash: commitment-hash, has-voted: false }
    )
    
    (ok true)
  )
)

(define-public (submit-zk-vote (poll-id uint) (nullifier-hash (buff 32)) (vote-option uint) (proof-hash (buff 32)))
  (let
    (
      (poll-data (unwrap! (map-get? polls { poll-id: poll-id }) ERR_POLL_NOT_FOUND))
      (existing-nullifier (map-get? nullifiers { nullifier-hash: nullifier-hash }))
      (option-count (len (get options poll-data)))
    )
    (asserts! (get is-active poll-data) ERR_POLL_ENDED)
    (asserts! (< stacks-block-height (get end-block poll-data)) ERR_POLL_ENDED)
    (asserts! (is-none existing-nullifier) ERR_NULLIFIER_USED)
    (asserts! (< vote-option option-count) ERR_INVALID_OPTION)
    (asserts! (> (len nullifier-hash) u0) ERR_INVALID_NULLIFIER)
    
    (map-set nullifiers
      { nullifier-hash: nullifier-hash }
      { poll-id: poll-id, used: true }
    )
    
    (map-set zk-proofs
      { poll-id: poll-id, proof-hash: proof-hash }
      { nullifier: nullifier-hash, vote-option: vote-option, is-valid: true }
    )
    
    (let
      (
        (current-votes (default-to u0 (get vote-count (map-get? poll-results { poll-id: poll-id, option-index: vote-option }))))
        (total-votes (get total-votes poll-data))
      )
      (map-set poll-results
        { poll-id: poll-id, option-index: vote-option }
        { vote-count: (+ current-votes u1) }
      )
      
      (map-set polls
        { poll-id: poll-id }
        (merge poll-data { total-votes: (+ total-votes u1) })
      )
    )
    
    (ok true)
  )
)

(define-public (end-poll (poll-id uint))
  (let
    (
      (poll-data (unwrap! (map-get? polls { poll-id: poll-id }) ERR_POLL_NOT_FOUND))
    )
    (asserts! (or (is-eq tx-sender (get creator poll-data)) (is-eq tx-sender CONTRACT_OWNER)) ERR_NOT_AUTHORIZED)
    (asserts! (get is-active poll-data) ERR_POLL_ENDED)
    
    (map-set polls
      { poll-id: poll-id }
      (merge poll-data { is-active: false })
    )
    
    (ok true)
  )
)

(define-public (verify-zk-proof (poll-id uint) (proof-hash (buff 32)) (public-inputs (list 5 uint)))
  (let
    (
      (proof-data (map-get? zk-proofs { poll-id: poll-id, proof-hash: proof-hash }))
    )
    (match proof-data
      proof-info
      (begin
        (asserts! (get is-valid proof-info) (err u109))
        (ok { 
          nullifier: (get nullifier proof-info),
          vote-option: (get vote-option proof-info),
          verified: true
        })
      )
      (err u110)
    )
  )
)

(define-read-only (get-poll (poll-id uint))
  (map-get? polls { poll-id: poll-id })
)

(define-read-only (get-poll-results (poll-id uint))
  (let
    (
      (poll-data (map-get? polls { poll-id: poll-id }))
    )
    (match poll-data
      poll-info
      (ok {
        poll-id: poll-id,
        title: (get title poll-info),
        total-votes: (get total-votes poll-info),
        is-active: (get is-active poll-info),
        results: (map get-option-votes (list u0 u1 u2 u3 u4 u5 u6 u7 u8 u9))
      })
      ERR_POLL_NOT_FOUND
    )
  )
)

(define-read-only (get-option-votes (option-index uint))
  (default-to u0 (get vote-count (map-get? poll-results { poll-id: u1, option-index: option-index })))
)

(define-read-only (get-commitment (poll-id uint) (commitment-hash (buff 32)))
  (map-get? commitments { poll-id: poll-id, commitment-hash: commitment-hash })
)

(define-read-only (has-nullifier-been-used (nullifier-hash (buff 32)))
  (is-some (map-get? nullifiers { nullifier-hash: nullifier-hash }))
)

(define-read-only (get-voter-commitment (voter principal) (poll-id uint))
  (map-get? voter-commitments { voter: voter, poll-id: poll-id })
)

(define-read-only (get-poll-count)
  (var-get poll-counter)
)

(define-read-only (is-poll-active (poll-id uint))
  (match (map-get? polls { poll-id: poll-id })
    poll-data (and (get is-active poll-data) (< stacks-block-height (get end-block poll-data)))
    false
  )
)

(define-read-only (get-zk-proof (poll-id uint) (proof-hash (buff 32)))
  (map-get? zk-proofs { poll-id: poll-id, proof-hash: proof-hash })
)

(define-private (generate-commitment (secret (buff 32)) (vote-option uint))
  (keccak256 (concat secret (buff-from-uint-be vote-option)))
)

(define-private (buff-from-uint-be (value uint))
  (unwrap-panic (to-consensus-buff? value))
)