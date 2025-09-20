;; Decentralized Wireless Billing Smart Contract
;; A comprehensive billing system for wireless services with subscription management,
;; usage tracking, payment processing, and dispute resolution

;; ========================================
;; CONSTANTS AND ERROR CODES
;; ========================================

;; Contract constants
(define-constant contract-owner tx-sender)
(define-constant min-plan-price u100) ;; Minimum price in microSTX
(define-constant max-plan-price u100000000) ;; Maximum price in microSTX
(define-constant dispute-window u144) ;; 24 hours in blocks (~10 min blocks)
(define-constant max-overage-multiplier u5) ;; Maximum 5x base rate for overages

;; Error codes
(define-constant err-owner-only (err u100))
(define-constant err-not-found (err u101))
(define-constant err-unauthorized (err u102))
(define-constant err-invalid-amount (err u103))
(define-constant err-insufficient-balance (err u104))
(define-constant err-plan-not-active (err u105))
(define-constant err-already-exists (err u106))
(define-constant err-invalid-parameters (err u107))
(define-constant err-payment-failed (err u108))
(define-constant err-dispute-window-closed (err u109))
(define-constant err-service-suspended (err u110))
(define-constant err-invalid-usage (err u111))
(define-constant err-refund-failed (err u112))
(define-constant err-invalid-input (err u113))

;; ========================================
;; DATA STRUCTURES
;; ========================================

;; Service plans offered by providers
(define-map service-plans
    { provider: principal, plan-id: uint }
    {
        name: (string-ascii 64),
        description: (string-ascii 256),
        base-price: uint, ;; Monthly price in microSTX
        data-limit: uint, ;; In MB
        voice-minutes: uint,
        sms-limit: uint,
        overage-data-rate: uint, ;; Per MB in microSTX
        overage-voice-rate: uint, ;; Per minute in microSTX
        overage-sms-rate: uint, ;; Per SMS in microSTX
        is-active: bool,
        created-at: uint
    }
)

;; User subscriptions
(define-map user-subscriptions
    { user: principal, provider: principal }
    {
        plan-id: uint,
        start-date: uint,
        end-date: uint,
        monthly-payment: uint,
        auto-renewal: bool,
        status: (string-ascii 16), ;; "active", "suspended", "cancelled"
        last-payment: uint,
        grace-period-end: uint
    }
)

;; Usage tracking for current billing cycle
(define-map usage-records
    { user: principal, provider: principal, cycle-start: uint }
    {
        data-used: uint, ;; In MB
        voice-used: uint, ;; In minutes
        sms-used: uint,
        last-updated: uint
    }
)

;; Billing records for transparency
(define-map billing-records
    { user: principal, provider: principal, cycle-start: uint }
    {
        base-charges: uint,
        overage-charges: uint,
        total-amount: uint,
        payment-status: (string-ascii 16), ;; "pending", "paid", "overdue", "disputed"
        due-date: uint,
        paid-date: uint,
        created-at: uint
    }
)

;; Payment history
(define-map payment-history
    uint ;; payment-id
    {
        user: principal,
        provider: principal,
        amount: uint,
        payment-type: (string-ascii 16), ;; "subscription", "overage", "deposit"
        transaction-id: (buff 32),
        timestamp: uint,
        status: (string-ascii 16) ;; "completed", "failed", "refunded"
    }
)

;; Dispute management
(define-map disputes
    uint ;; dispute-id
    {
        user: principal,
        provider: principal,
        bill-cycle: uint,
        disputed-amount: uint,
        reason: (string-ascii 256),
        status: (string-ascii 16), ;; "open", "resolved", "rejected"
        created-at: uint,
        resolved-at: uint,
        resolution: (string-ascii 256)
    }
)

;; Provider settings and reputation
(define-map providers
    principal
    {
        name: (string-ascii 64),
        description: (string-ascii 256),
        is-active: bool,
        reputation-score: uint, ;; Out of 100
        total-customers: uint,
        registered-at: uint,
        contact-info: (string-ascii 128)
    }
)

;; User balances and deposits
(define-map user-balances
    principal
    {
        balance: uint,
        locked-balance: uint, ;; For pending payments
        last-updated: uint
    }
)

;; ========================================
;; DATA VARIABLES
;; ========================================

(define-data-var next-plan-id uint u1)
(define-data-var next-payment-id uint u1)
(define-data-var next-dispute-id uint u1)
(define-data-var contract-active bool true)
(define-data-var emergency-stop bool false)

;; ========================================
;; PRIVATE HELPER FUNCTIONS
;; ========================================

;; Check if caller is contract owner
(define-private (is-owner (caller principal))
    (is-eq caller contract-owner)
)

;; Get current block height
(define-private (get-current-block)
    stacks-block-height
)

;; Calculate billing cycle start (monthly cycles)
(define-private (get-cycle-start (timestamp uint))
    (let ((blocks-per-month u4320)) ;; Approximately 30 days
        (- timestamp (mod timestamp blocks-per-month))
    )
)

;; Validate plan parameters
(define-private (validate-plan-params (price uint) (data-limit uint) (voice uint) (sms uint))
    (and
        (>= price min-plan-price)
        (<= price max-plan-price)
        (> data-limit u0)
        (> voice u0)
        (> sms u0)
    )
)

;; Validate string inputs to prevent empty strings
(define-private (is-valid-string (input (string-ascii 256)))
    (> (len input) u0)
)

;; Validate string inputs for names (shorter strings)
(define-private (is-valid-name (input (string-ascii 64)))
    (> (len input) u0)
)

;; Validate contact info
(define-private (is-valid-contact (input (string-ascii 128)))
    (> (len input) u0)
)

;; Validate principal is not contract address
(define-private (is-valid-principal (addr principal))
    (not (is-eq addr (as-contract tx-sender)))
)

;; Validate overage rates are reasonable
(define-private (validate-overage-rates (data-rate uint) (voice-rate uint) (sms-rate uint) (base-price uint))
    (and
        (<= data-rate (* base-price max-overage-multiplier))
        (<= voice-rate (* base-price max-overage-multiplier))
        (<= sms-rate (* base-price max-overage-multiplier))
    )
)

;; Calculate overage charges
(define-private (calculate-overage-charges 
    (data-used uint) (voice-used uint) (sms-used uint)
    (data-limit uint) (voice-limit uint) (sms-limit uint)
    (data-rate uint) (voice-rate uint) (sms-rate uint))
    (let
        (
            (data-overage (if (> data-used data-limit) (- data-used data-limit) u0))
            (voice-overage (if (> voice-used voice-limit) (- voice-used voice-limit) u0))
            (sms-overage (if (> sms-used sms-limit) (- sms-used sms-limit) u0))
        )
        (+ 
            (* data-overage data-rate)
            (* voice-overage voice-rate)
            (* sms-overage sms-rate)
        )
    )
)

;; ========================================
;; PUBLIC FUNCTIONS - PROVIDER MANAGEMENT
;; ========================================

;; Register as a service provider
(define-public (register-provider (name (string-ascii 64)) (description (string-ascii 256)) (contact (string-ascii 128)))
    (let ((current-block (get-current-block)))
        (asserts! (var-get contract-active) err-service-suspended)
        (asserts! (is-none (map-get? providers tx-sender)) err-already-exists)
        ;; Validate all string inputs
        (asserts! (is-valid-name name) err-invalid-parameters)
        (asserts! (is-valid-string description) err-invalid-parameters)
        (asserts! (is-valid-contact contact) err-invalid-parameters)
        
        (map-set providers tx-sender
            {
                name: name,
                description: description,
                is-active: true,
                reputation-score: u50, ;; Starting neutral score
                total-customers: u0,
                registered-at: current-block,
                contact-info: contact
            }
        )
        (ok true)
    )
)

;; Create a new service plan
(define-public (create-service-plan 
    (name (string-ascii 64)) 
    (description (string-ascii 256))
    (base-price uint)
    (data-limit uint)
    (voice-minutes uint)
    (sms-limit uint)
    (overage-data-rate uint)
    (overage-voice-rate uint)
    (overage-sms-rate uint))
    (let 
        (
            (plan-id (var-get next-plan-id))
            (current-block (get-current-block))
        )
        (asserts! (var-get contract-active) err-service-suspended)
        (asserts! (is-some (map-get? providers tx-sender)) err-unauthorized)
        ;; Validate plan parameters
        (asserts! (validate-plan-params base-price data-limit voice-minutes sms-limit) err-invalid-parameters)
        (asserts! (is-valid-name name) err-invalid-parameters)
        (asserts! (is-valid-string description) err-invalid-parameters)
        ;; Validate overage rates are reasonable
        (asserts! (validate-overage-rates overage-data-rate overage-voice-rate overage-sms-rate base-price) err-invalid-parameters)
        
        (map-set service-plans 
            { provider: tx-sender, plan-id: plan-id }
            {
                name: name,
                description: description,
                base-price: base-price,
                data-limit: data-limit,
                voice-minutes: voice-minutes,
                sms-limit: sms-limit,
                overage-data-rate: overage-data-rate,
                overage-voice-rate: overage-voice-rate,
                overage-sms-rate: overage-sms-rate,
                is-active: true,
                created-at: current-block
            }
        )
        
        (var-set next-plan-id (+ plan-id u1))
        (ok plan-id)
    )
)

;; Update service plan
(define-public (update-service-plan 
    (plan-id uint)
    (base-price uint)
    (data-limit uint)
    (voice-minutes uint)
    (sms-limit uint)
    (overage-data-rate uint)
    (overage-voice-rate uint)
    (overage-sms-rate uint))
    (let ((plan (map-get? service-plans { provider: tx-sender, plan-id: plan-id })))
        (asserts! (var-get contract-active) err-service-suspended)
        ;; Validate plan-id is reasonable
        (asserts! (> plan-id u0) err-invalid-parameters)
        (asserts! (is-some plan) err-not-found)
        ;; Validate plan parameters
        (asserts! (validate-plan-params base-price data-limit voice-minutes sms-limit) err-invalid-parameters)
        ;; Validate overage rates are reasonable
        (asserts! (validate-overage-rates overage-data-rate overage-voice-rate overage-sms-rate base-price) err-invalid-parameters)
        
        (map-set service-plans 
            { provider: tx-sender, plan-id: plan-id }
            (merge (unwrap-panic plan)
                {
                    base-price: base-price,
                    data-limit: data-limit,
                    voice-minutes: voice-minutes,
                    sms-limit: sms-limit,
                    overage-data-rate: overage-data-rate,
                    overage-voice-rate: overage-voice-rate,
                    overage-sms-rate: overage-sms-rate
                }
            )
        )
        (ok true)
    )
)

;; Deactivate service plan
(define-public (deactivate-plan (plan-id uint))
    (let ((plan (map-get? service-plans { provider: tx-sender, plan-id: plan-id })))
        (asserts! (var-get contract-active) err-service-suspended)
        (asserts! (is-some plan) err-not-found)
        ;; Validate plan-id is reasonable
        (asserts! (> plan-id u0) err-invalid-parameters)
        
        (map-set service-plans 
            { provider: tx-sender, plan-id: plan-id }
            (merge (unwrap-panic plan) { is-active: false })
        )
        (ok true)
    )
)

;; ========================================
;; PUBLIC FUNCTIONS - USER SUBSCRIPTION
;; ========================================

;; Subscribe to a service plan
(define-public (subscribe-to-plan (provider principal) (plan-id uint) (auto-renewal bool))
    (let 
        (
            (plan (map-get? service-plans { provider: provider, plan-id: plan-id }))
            (current-block (get-current-block))
            (end-date (+ current-block u4320)) ;; 30 days
            (user-balance (default-to { balance: u0, locked-balance: u0, last-updated: u0 } 
                         (map-get? user-balances tx-sender)))
        )
        (asserts! (var-get contract-active) err-service-suspended)
        ;; Validate inputs
        (asserts! (is-valid-principal provider) err-invalid-parameters)
        (asserts! (> plan-id u0) err-invalid-parameters)
        (asserts! (is-some plan) err-not-found)
        (asserts! (get is-active (unwrap-panic plan)) err-plan-not-active)
        (asserts! (is-none (map-get? user-subscriptions { user: tx-sender, provider: provider })) err-already-exists)
        
        (let ((plan-details (unwrap-panic plan)))
            (asserts! (>= (get balance user-balance) (get base-price plan-details)) err-insufficient-balance)
            
            ;; Deduct payment from user balance
            (map-set user-balances tx-sender
                (merge user-balance 
                    { 
                        balance: (- (get balance user-balance) (get base-price plan-details)),
                        last-updated: current-block
                    }
                )
            )
            
            ;; Create subscription
            (map-set user-subscriptions 
                { user: tx-sender, provider: provider }
                {
                    plan-id: plan-id,
                    start-date: current-block,
                    end-date: end-date,
                    monthly-payment: (get base-price plan-details),
                    auto-renewal: auto-renewal,
                    status: "active",
                    last-payment: current-block,
                    grace-period-end: (+ end-date u144) ;; 1 day grace period
                }
            )
            
            ;; Initialize usage tracking
            (map-set usage-records 
                { user: tx-sender, provider: provider, cycle-start: (get-cycle-start current-block) }
                {
                    data-used: u0,
                    voice-used: u0,
                    sms-used: u0,
                    last-updated: current-block
                }
            )
            
            ;; Update provider customer count
            (let ((provider-info (map-get? providers provider)))
                (if (is-some provider-info)
                    (map-set providers provider
                        (merge (unwrap-panic provider-info)
                            { total-customers: (+ (get total-customers (unwrap-panic provider-info)) u1) }
                        )
                    )
                    false
                )
            )
            
            (ok true)
        )
    )
)

;; Cancel subscription
(define-public (cancel-subscription (provider principal))
    (let 
        (
            (subscription (map-get? user-subscriptions { user: tx-sender, provider: provider }))
            (current-block (get-current-block))
        )
        (asserts! (var-get contract-active) err-service-suspended)
        ;; Validate provider
        (asserts! (is-valid-principal provider) err-invalid-parameters)
        (asserts! (is-some subscription) err-not-found)
        
        (map-set user-subscriptions 
            { user: tx-sender, provider: provider }
            (merge (unwrap-panic subscription) 
                { 
                    status: "cancelled",
                    auto-renewal: false
                }
            )
        )
        (ok true)
    )
)

;; Deposit funds to user balance
(define-public (deposit-funds (amount uint))
    (let 
        (
            (current-balance (default-to { balance: u0, locked-balance: u0, last-updated: u0 } 
                             (map-get? user-balances tx-sender)))
            (current-block (get-current-block))
        )
        (asserts! (var-get contract-active) err-service-suspended)
        (asserts! (> amount u0) err-invalid-amount)
        ;; Validate amount is reasonable (prevent overflow)
        (asserts! (< amount u1000000000000) err-invalid-amount)
        
        ;; Transfer STX to contract (this would be handled by the STX transfer in practice)
        (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
        
        ;; Update user balance
        (map-set user-balances tx-sender
            {
                balance: (+ (get balance current-balance) amount),
                locked-balance: (get locked-balance current-balance),
                last-updated: current-block
            }
        )
        
        (ok true)
    )
)

;; ========================================
;; PUBLIC FUNCTIONS - USAGE TRACKING
;; ========================================

;; Record usage (only providers can call this for their customers)
(define-public (record-usage 
    (user principal) 
    (data-mb uint) 
    (voice-minutes uint) 
    (sms-count uint))
    (let 
        (
            (subscription (map-get? user-subscriptions { user: user, provider: tx-sender }))
            (current-block (get-current-block))
            (cycle-start (get-cycle-start current-block))
            (current-usage (default-to 
                { data-used: u0, voice-used: u0, sms-used: u0, last-updated: u0 }
                (map-get? usage-records { user: user, provider: tx-sender, cycle-start: cycle-start })
            ))
        )
        (asserts! (var-get contract-active) err-service-suspended)
        ;; Validate user principal
        (asserts! (is-valid-principal user) err-invalid-parameters)
        ;; Validate usage amounts are reasonable
        (asserts! (< data-mb u1000000) err-invalid-usage) ;; Max 1TB per call
        (asserts! (< voice-minutes u100000) err-invalid-usage) ;; Max ~1600 hours per call
        (asserts! (< sms-count u100000) err-invalid-usage) ;; Max 100k SMS per call
        (asserts! (is-some subscription) err-unauthorized)
        (asserts! (is-eq (get status (unwrap-panic subscription)) "active") err-service-suspended)
        (asserts! (or (> data-mb u0) (> voice-minutes u0) (> sms-count u0)) err-invalid-usage)
        
        ;; Update usage records
        (map-set usage-records 
            { user: user, provider: tx-sender, cycle-start: cycle-start }
            {
                data-used: (+ (get data-used current-usage) data-mb),
                voice-used: (+ (get voice-used current-usage) voice-minutes),
                sms-used: (+ (get sms-used current-usage) sms-count),
                last-updated: current-block
            }
        )
        
        (ok true)
    )
)

;; Generate bill for billing cycle
(define-public (generate-bill (user principal) (cycle-start uint))
    (let 
        (
            (subscription (map-get? user-subscriptions { user: user, provider: tx-sender }))
            (plan (map-get? service-plans { provider: tx-sender, plan-id: (get plan-id (unwrap! subscription err-not-found)) }))
            (usage (map-get? usage-records { user: user, provider: tx-sender, cycle-start: cycle-start }))
            (current-block (get-current-block))
        )
        (asserts! (var-get contract-active) err-service-suspended)
        ;; Validate inputs
        (asserts! (is-valid-principal user) err-invalid-parameters)
        (asserts! (> cycle-start u0) err-invalid-parameters)
        (asserts! (<= cycle-start current-block) err-invalid-parameters)
        (asserts! (is-some subscription) err-not-found)
        (asserts! (is-some plan) err-not-found)
        (asserts! (is-some usage) err-not-found)
        
        (let 
            (
                (plan-details (unwrap-panic plan))
                (usage-details (unwrap-panic usage))
                (base-charges (get monthly-payment (unwrap-panic subscription)))
                (overage-charges (calculate-overage-charges
                    (get data-used usage-details)
                    (get voice-used usage-details)
                    (get sms-used usage-details)
                    (get data-limit plan-details)
                    (get voice-minutes plan-details)
                    (get sms-limit plan-details)
                    (get overage-data-rate plan-details)
                    (get overage-voice-rate plan-details)
                    (get overage-sms-rate plan-details)
                ))
                (total-amount (+ base-charges overage-charges))
            )
            
            ;; Create billing record
            (map-set billing-records 
                { user: user, provider: tx-sender, cycle-start: cycle-start }
                {
                    base-charges: base-charges,
                    overage-charges: overage-charges,
                    total-amount: total-amount,
                    payment-status: "pending",
                    due-date: (+ current-block u432), ;; 3 days to pay
                    paid-date: u0,
                    created-at: current-block
                }
            )
            
            (ok total-amount)
        )
    )
)

;; Process payment for bill
(define-public (pay-bill (provider principal) (cycle-start uint))
    (let 
        (
            (bill (map-get? billing-records { user: tx-sender, provider: provider, cycle-start: cycle-start }))
            (user-balance (map-get? user-balances tx-sender))
            (current-block (get-current-block))
            (payment-id (var-get next-payment-id))
        )
        (asserts! (var-get contract-active) err-service-suspended)
        ;; Validate inputs
        (asserts! (is-valid-principal provider) err-invalid-parameters)
        (asserts! (> cycle-start u0) err-invalid-parameters)
        (asserts! (<= cycle-start current-block) err-invalid-parameters)
        (asserts! (is-some bill) err-not-found)
        (asserts! (is-some user-balance) err-insufficient-balance)
        
        (let 
            (
                (bill-details (unwrap-panic bill))
                (balance-details (unwrap-panic user-balance))
                (amount-due (get total-amount bill-details))
            )
            (asserts! (>= (get balance balance-details) amount-due) err-insufficient-balance)
            
            ;; Update user balance
            (map-set user-balances tx-sender
                (merge balance-details 
                    { 
                        balance: (- (get balance balance-details) amount-due),
                        last-updated: current-block
                    }
                )
            )
            
            ;; Update bill status
            (map-set billing-records 
                { user: tx-sender, provider: provider, cycle-start: cycle-start }
                (merge bill-details 
                    { 
                        payment-status: "paid",
                        paid-date: current-block
                    }
                )
            )
            
            ;; Record payment
            (map-set payment-history payment-id
                {
                    user: tx-sender,
                    provider: provider,
                    amount: amount-due,
                    payment-type: "subscription    ",
                    transaction-id: (unwrap-panic (as-max-len? (unwrap-panic (to-consensus-buff? tx-sender)) u32)),
                    timestamp: current-block,
                    status: "completed       "
                }
            )
            
            (var-set next-payment-id (+ payment-id u1))
            (ok true)
        )
    )
)

;; ========================================
;; PUBLIC FUNCTIONS - DISPUTE RESOLUTION
;; ========================================

;; File a dispute
(define-public (file-dispute 
    (provider principal) 
    (bill-cycle uint) 
    (disputed-amount uint) 
    (reason (string-ascii 256)))
    (let 
        (
            (bill (map-get? billing-records { user: tx-sender, provider: provider, cycle-start: bill-cycle }))
            (current-block (get-current-block))
            (dispute-id (var-get next-dispute-id))
        )
        (asserts! (var-get contract-active) err-service-suspended)
        ;; Validate inputs
        (asserts! (is-valid-principal provider) err-invalid-parameters)
        (asserts! (> bill-cycle u0) err-invalid-parameters)
        (asserts! (<= bill-cycle current-block) err-invalid-parameters)
        (asserts! (is-valid-string reason) err-invalid-parameters)
        (asserts! (is-some bill) err-not-found)
        (asserts! (> disputed-amount u0) err-invalid-amount)
        
        (let ((bill-details (unwrap-panic bill)))
            (asserts! (<= disputed-amount (get total-amount bill-details)) err-invalid-amount)
            (asserts! (<= (- current-block (get created-at bill-details)) dispute-window) err-dispute-window-closed)
            
            ;; Create dispute
            (map-set disputes dispute-id
                {
                    user: tx-sender,
                    provider: provider,
                    bill-cycle: bill-cycle,
                    disputed-amount: disputed-amount,
                    reason: reason,
                    status: "open",
                    created-at: current-block,
                    resolved-at: u0,
                    resolution: ""
                }
            )
            
            ;; Update bill status
            (map-set billing-records 
                { user: tx-sender, provider: provider, cycle-start: bill-cycle }
                (merge bill-details { payment-status: "disputed" })
            )
            
            (var-set next-dispute-id (+ dispute-id u1))
            (ok dispute-id)
        )
    )
)

;; Resolve dispute (only contract owner for now)
(define-public (resolve-dispute 
    (dispute-id uint) 
    (resolution (string-ascii 256)) 
    (refund-amount uint))
    (let 
        (
            (dispute (map-get? disputes dispute-id))
            (current-block (get-current-block))
        )
        (asserts! (is-owner tx-sender) err-owner-only)
        ;; Validate inputs
        (asserts! (> dispute-id u0) err-invalid-parameters)
        (asserts! (is-valid-string resolution) err-invalid-parameters)
        (asserts! (is-some dispute) err-not-found)
        
        (let ((dispute-details (unwrap-panic dispute)))
            (asserts! (is-eq (get status dispute-details) "open") err-unauthorized)
            ;; Validate refund amount is not greater than disputed amount
            (asserts! (<= refund-amount (get disputed-amount dispute-details)) err-invalid-amount)
            
            ;; Update dispute
            (map-set disputes dispute-id
                (merge dispute-details
                    {
                        status: "resolved",
                        resolved-at: current-block,
                        resolution: resolution
                    }
                )
            )
            
            ;; Process refund if applicable
            (if (> refund-amount u0)
                (let ((user-balance (default-to { balance: u0, locked-balance: u0, last-updated: u0 } 
                                     (map-get? user-balances (get user dispute-details)))))
                    (map-set user-balances (get user dispute-details)
                        (merge user-balance 
                            { 
                                balance: (+ (get balance user-balance) refund-amount),
                                last-updated: current-block
                            }
                        )
                    )
                )
                true
            )
            
            (ok true)
        )
    )
)

;; ========================================
;; READ-ONLY FUNCTIONS
;; ========================================

;; Get service plan details
(define-read-only (get-service-plan (provider principal) (plan-id uint))
    (map-get? service-plans { provider: provider, plan-id: plan-id })
)

;; Get user subscription
(define-read-only (get-user-subscription (user principal) (provider principal))
    (map-get? user-subscriptions { user: user, provider: provider })
)

;; Get usage for current cycle
(define-read-only (get-current-usage (user principal) (provider principal))
    (let ((cycle-start (get-cycle-start (get-current-block))))
        (map-get? usage-records { user: user, provider: provider, cycle-start: cycle-start })
    )
)

;; Get billing record
(define-read-only (get-billing-record (user principal) (provider principal) (cycle-start uint))
    (map-get? billing-records { user: user, provider: provider, cycle-start: cycle-start })
)

;; Get user balance
(define-read-only (get-user-balance (user principal))
    (map-get? user-balances user)
)

;; Get provider info
(define-read-only (get-provider-info (provider principal))
    (map-get? providers provider)
)

;; Get dispute details
(define-read-only (get-dispute (dispute-id uint))
    (map-get? disputes dispute-id)
)

;; Get payment details
(define-read-only (get-payment (payment-id uint))
    (map-get? payment-history payment-id)
)

;; Check if service is active for user
(define-read-only (is-service-active (user principal) (provider principal))
    (let ((subscription (map-get? user-subscriptions { user: user, provider: provider })))
        (if (is-some subscription)
            (let ((sub-details (unwrap-panic subscription)))
                (and 
                    (is-eq (get status sub-details) "active")
                    (> (get end-date sub-details) (get-current-block))
                )
            )
            false
        )
    )
)

;; ========================================
;; ADMIN FUNCTIONS
;; ========================================

;; Emergency stop
(define-public (set-emergency-stop (stop bool))
    (begin
        (asserts! (is-owner tx-sender) err-owner-only)
        (var-set emergency-stop stop)
        (var-set contract-active (not stop))
        (ok true)
    )
)

;; Update provider reputation (admin function)
(define-public (update-provider-reputation (provider principal) (new-score uint))
    (let ((provider-info (map-get? providers provider)))
        (asserts! (is-owner tx-sender) err-owner-only)
        ;; Validate inputs
        (asserts! (is-valid-principal provider) err-invalid-parameters)
        (asserts! (is-some provider-info) err-not-found)
        (asserts! (<= new-score u100) err-invalid-parameters)
        
        (map-set providers provider
            (merge (unwrap-panic provider-info) { reputation-score: new-score })
        )
        (ok true)
    )
)