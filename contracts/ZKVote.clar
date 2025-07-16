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
(define-constant ERR_INSUFFICIENT_STAKE (err u109))
(define-constant ERR_STAKE_ALREADY_EXISTS (err u110))
(define-constant ERR_NO_STAKE_FOUND (err u111))
(define-constant ERR_STAKE_LOCKED (err u112))
(define-constant ERR_INSUFFICIENT_REPUTATION (err u113))
(define-constant ERR_INVALID_AMOUNT (err u114))

(define-data-var poll-counter uint u0)
(define-data-var minimum-stake uint u1000000)
(define-data-var base-reputation uint u100)
(define-data-var stake-lock-period uint u144)

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

(define-map voter-stakes
  { voter: principal }
  { 
    staked-amount: uint,
    stake-block: uint,
    reputation-score: uint,
    total-votes: uint,
    successful-votes: uint,
    is-active: bool
  }
)

(define-map poll-stakes
  { poll-id: uint, voter: principal }
  {
    staked-amount: uint,
    voting-weight: uint,
    reward-earned: uint,
    is-slashed: bool
  }
)

(define-map reputation-history
  { voter: principal, poll-id: uint }
  {
    reputation-change: int,
    final-reputation: uint,
    vote-outcome: bool
  }
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

(define-public (stake-for-voting (amount uint))
  (let
    (
      (existing-stake (map-get? voter-stakes { voter: tx-sender }))
      (min-stake (var-get minimum-stake))
    )
    (asserts! (>= amount min-stake) ERR_INSUFFICIENT_STAKE)
    (asserts! (is-none existing-stake) ERR_STAKE_ALREADY_EXISTS)
    (asserts! (> amount u0) ERR_INVALID_AMOUNT)
    
    (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
    
    (map-set voter-stakes
      { voter: tx-sender }
      {
        staked-amount: amount,
        stake-block: stacks-block-height,
        reputation-score: (var-get base-reputation),
        total-votes: u0,
        successful-votes: u0,
        is-active: true
      }
    )
    
    (ok amount)
  )
)

(define-public (increase-stake (additional-amount uint))
  (let
    (
      (stake-data (unwrap! (map-get? voter-stakes { voter: tx-sender }) ERR_NO_STAKE_FOUND))
    )
    (asserts! (get is-active stake-data) ERR_STAKE_LOCKED)
    (asserts! (> additional-amount u0) ERR_INVALID_AMOUNT)
    
    (try! (stx-transfer? additional-amount tx-sender (as-contract tx-sender)))
    
    (map-set voter-stakes
      { voter: tx-sender }
      (merge stake-data { staked-amount: (+ (get staked-amount stake-data) additional-amount) })
    )
    
    (ok (+ (get staked-amount stake-data) additional-amount))
  )
)

(define-public (withdraw-stake)
  (let
    (
      (stake-data (unwrap! (map-get? voter-stakes { voter: tx-sender }) ERR_NO_STAKE_FOUND))
      (stake-amount (get staked-amount stake-data))
      (lock-period (var-get stake-lock-period))
    )
    (asserts! (get is-active stake-data) ERR_STAKE_LOCKED)
    (asserts! (>= stacks-block-height (+ (get stake-block stake-data) lock-period)) ERR_STAKE_LOCKED)
    
    (try! (as-contract (stx-transfer? stake-amount tx-sender tx-sender)))
    
    (map-delete voter-stakes { voter: tx-sender })
    
    (ok stake-amount)
  )
)

(define-public (calculate-voting-weight (voter principal) (poll-id uint))
  (let
    (
      (stake-data (unwrap! (map-get? voter-stakes { voter: voter }) ERR_NO_STAKE_FOUND))
      (base-weight (get staked-amount stake-data))
      (reputation (get reputation-score stake-data))
      (reputation-multiplier (/ reputation u100))
    )
    (asserts! (get is-active stake-data) ERR_STAKE_LOCKED)
    
    (let
      (
        (voting-weight (+ base-weight (* base-weight reputation-multiplier)))
      )
      (map-set poll-stakes
        { poll-id: poll-id, voter: voter }
        {
          staked-amount: base-weight,
          voting-weight: voting-weight,
          reward-earned: u0,
          is-slashed: false
        }
      )
      
      (ok voting-weight)
    )
  )
)

(define-public (update-reputation (voter principal) (poll-id uint) (vote-successful bool))
  (let
    (
      (stake-data (unwrap! (map-get? voter-stakes { voter: voter }) ERR_NO_STAKE_FOUND))
      (current-reputation (get reputation-score stake-data))
      (total-votes (get total-votes stake-data))
      (successful-votes (get successful-votes stake-data))
      (reputation-change (if vote-successful 10 -5))
      (new-reputation (if vote-successful 
        (+ current-reputation (to-uint reputation-change))
        (if (>= current-reputation u5) (- current-reputation u5) u0)))
      (new-successful-votes (if vote-successful (+ successful-votes u1) successful-votes))
    )
    (asserts! (or (is-eq tx-sender CONTRACT_OWNER) (is-eq tx-sender voter)) ERR_NOT_AUTHORIZED)
    
    (map-set voter-stakes
      { voter: voter }
      (merge stake-data {
        reputation-score: new-reputation,
        total-votes: (+ total-votes u1),
        successful-votes: new-successful-votes
      })
    )
    
    (map-set reputation-history
      { voter: voter, poll-id: poll-id }
      {
        reputation-change: reputation-change,
        final-reputation: new-reputation,
        vote-outcome: vote-successful
      }
    )
    
    (ok new-reputation)
  )
)

(define-public (slash-stake (voter principal) (poll-id uint) (slash-percentage uint))
  (let
    (
      (stake-data (unwrap! (map-get? voter-stakes { voter: voter }) ERR_NO_STAKE_FOUND))
      (poll-stake-data (unwrap! (map-get? poll-stakes { poll-id: poll-id, voter: voter }) ERR_NO_STAKE_FOUND))
      (staked-amount (get staked-amount poll-stake-data))
      (slash-amount (/ (* staked-amount slash-percentage) u100))
      (remaining-amount (- staked-amount slash-amount))
    )
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_NOT_AUTHORIZED)
    (asserts! (<= slash-percentage u100) ERR_INVALID_AMOUNT)
    (asserts! (not (get is-slashed poll-stake-data)) ERR_STAKE_LOCKED)
    
    (map-set voter-stakes
      { voter: voter }
      (merge stake-data { staked-amount: remaining-amount })
    )
    
    (map-set poll-stakes
      { poll-id: poll-id, voter: voter }
      (merge poll-stake-data { is-slashed: true })
    )
    
    (ok slash-amount)
  )
)

(define-public (distribute-rewards (poll-id uint) (voters (list 100 principal)) (reward-amounts (list 100 uint)))
  (let
    (
      (poll-data (unwrap! (map-get? polls { poll-id: poll-id }) ERR_POLL_NOT_FOUND))
    )
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_NOT_AUTHORIZED)
    (asserts! (not (get is-active poll-data)) ERR_POLL_ACTIVE)
    
    (fold process-reward-distribution 
      (zip voters reward-amounts)
      { poll-id: poll-id, success: true }
    )
    
    (ok true)
  )
)

(define-private (process-reward-distribution (voter-reward { voter: principal, reward: uint }) (context { poll-id: uint, success: bool }))
  (let
    (
      (voter (get voter voter-reward))
      (reward (get reward voter-reward))
      (poll-id (get poll-id context))
      (poll-stake-data (map-get? poll-stakes { poll-id: poll-id, voter: voter }))
    )
    (match poll-stake-data
      stake-info
      (begin
        (map-set poll-stakes
          { poll-id: poll-id, voter: voter }
          (merge stake-info { reward-earned: reward })
        )
        (unwrap-panic (as-contract (stx-transfer? reward tx-sender voter)))
        context
      )
      context
    )
  )
)

(define-private (zip (list-a (list 100 principal)) (list-b (list 100 uint)))
  (map create-pair-entry list-a list-b)
)

(define-private (create-pair-entry (voter principal) (reward uint))
  { voter: voter, reward: reward }
)

(define-read-only (get-voter-stake (voter principal))
  (map-get? voter-stakes { voter: voter })
)

(define-read-only (get-poll-stake (poll-id uint) (voter principal))
  (map-get? poll-stakes { poll-id: poll-id, voter: voter })
)

(define-read-only (get-reputation-history (voter principal) (poll-id uint))
  (map-get? reputation-history { voter: voter, poll-id: poll-id })
)

(define-read-only (calculate-reputation-score (voter principal))
  (match (map-get? voter-stakes { voter: voter })
    stake-data
    (let
      (
        (total-votes (get total-votes stake-data))
        (successful-votes (get successful-votes stake-data))
        (success-rate (if (> total-votes u0) (/ (* successful-votes u100) total-votes) u0))
      )
      (ok {
        reputation-score: (get reputation-score stake-data),
        total-votes: total-votes,
        successful-votes: successful-votes,
        success-rate: success-rate
      })
    )
    ERR_NO_STAKE_FOUND
  )
)

(define-read-only (get-minimum-stake)
  (var-get minimum-stake)
)

(define-read-only (get-base-reputation)
  (var-get base-reputation)
)

(define-read-only (get-stake-lock-period)
  (var-get stake-lock-period)
)

(define-read-only (is-eligible-to-vote (voter principal) (poll-id uint))
  (match (map-get? voter-stakes { voter: voter })
    stake-data
    (and 
      (get is-active stake-data)
      (>= (get staked-amount stake-data) (var-get minimum-stake))
      (>= (get reputation-score stake-data) u50)
    )
    false
  )
)