;; Tests for lux-bridge.clar
;;
;; Run with: clarinet test
;; These tests use Clarinet's Clarity testing conventions.
;; Each test is a public function that returns (ok true) on success.

(use-trait ft-trait 'SP3FBR2AGK5H9QBDH3EEN6DF8EK8JY7RX8QJ5SVTE.sip-010-trait-ft-standard.sip-010-trait)

;; ============================================================
;; Helpers
;; ============================================================

(define-constant DEPLOYER 'ST1PQHQKV0RJXZFY1DGX8MNSNYVE3VGZJSRTPGZGM)
(define-constant WALLET_1 'ST1SJ3DTE5DN7X54YDH5D64R3BCB6A2AG2ZQ8YPD5)
(define-constant WALLET_2 'ST2CY5V39NHDPWSXMW9QDT3HC3GD6Q6XX4CFRK9AG)

(define-constant SIGNER_1 0x0279be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798)
(define-constant SIGNER_2 0x02c6047f9441ed7d6d3045406e95c07cd85c778e4b8cef3ca7abac09b95c709ee5)
(define-constant SIGNER_3 0x02f9308a019258c31049344f85f89d5229b531c845836f99b08601f113bce036f9)

(define-constant DUMMY_RECIPIENT 0x0000000000000000000000000000000000000000000000000000000000000001)
(define-constant DEST_CHAIN u96369) ;; Lux C-Chain

;; ============================================================
;; Test: initial state
;; ============================================================

(define-public (test-initial-state)
    (begin
        (asserts! (is-eq (contract-call? .lux-bridge get-paused) false) (err u1000))
        (asserts! (is-eq (contract-call? .lux-bridge get-nonce) u0) (err u1001))
        (asserts! (is-eq (contract-call? .lux-bridge get-total-locked) u0) (err u1002))
        (asserts! (is-eq (contract-call? .lux-bridge get-total-burned) u0) (err u1003))
        (ok true)))

;; ============================================================
;; Test: lock-and-bridge
;; ============================================================

(define-public (test-lock-and-bridge-ok)
    (let (
        (result (contract-call? .lux-bridge lock-and-bridge u1000000 DEST_CHAIN DUMMY_RECIPIENT))
    )
        ;; Should succeed and return nonce 1
        (asserts! (is-ok result) (err u2000))
        (asserts! (is-eq (unwrap-panic result) u1) (err u2001))
        ;; Nonce incremented
        (asserts! (is-eq (contract-call? .lux-bridge get-nonce) u1) (err u2002))
        ;; Total locked updated (amount minus fee: 1000000 * 30 / 10000 = 3000 fee)
        (asserts! (is-eq (contract-call? .lux-bridge get-total-locked) u997000) (err u2003))
        (ok true)))

(define-public (test-lock-and-bridge-zero-amount)
    (let (
        (result (contract-call? .lux-bridge lock-and-bridge u0 DEST_CHAIN DUMMY_RECIPIENT))
    )
        ;; Should fail with ERR_AMOUNT_ZERO (u105)
        (asserts! (is-err result) (err u2100))
        (asserts! (is-eq result (err u105)) (err u2101))
        (ok true)))

(define-public (test-lock-and-bridge-increments-nonce)
    (begin
        ;; First lock
        (unwrap-panic (contract-call? .lux-bridge lock-and-bridge u500000 DEST_CHAIN DUMMY_RECIPIENT))
        (asserts! (is-eq (contract-call? .lux-bridge get-nonce) u1) (err u2200))
        ;; Second lock
        (unwrap-panic (contract-call? .lux-bridge lock-and-bridge u500000 DEST_CHAIN DUMMY_RECIPIENT))
        (asserts! (is-eq (contract-call? .lux-bridge get-nonce) u2) (err u2201))
        (ok true)))

;; ============================================================
;; Test: mint-bridged
;; ============================================================

(define-public (test-mint-zero-amount)
    (let (
        (result (contract-call? .lux-bridge mint-bridged
            u96369 u1 WALLET_1 u0
            0x00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000ff
            SIGNER_1))
    )
        ;; Should fail with ERR_AMOUNT_ZERO
        (asserts! (is-err result) (err u3000))
        (asserts! (is-eq result (err u105)) (err u3001))
        (ok true)))

(define-public (test-mint-unauthorized-signer)
    (let (
        (bad-signer 0x02aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa)
        (result (contract-call? .lux-bridge mint-bridged
            u96369 u1 WALLET_1 u1000000
            0x00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000ff
            bad-signer))
    )
        ;; Should fail with ERR_UNAUTHORIZED (u108) -- signer not in set
        (asserts! (is-err result) (err u3100))
        (asserts! (is-eq result (err u108)) (err u3101))
        (ok true)))

(define-public (test-mint-duplicate-nonce)
    (begin
        ;; First: set signers so we have authorized keys
        (unwrap-panic (contract-call? .lux-bridge set-signers SIGNER_1 SIGNER_2 SIGNER_3))

        ;; First mint with nonce 1 (signature verification commented out in contract)
        (unwrap-panic (contract-call? .lux-bridge mint-bridged
            u96369 u1 WALLET_1 u1000000
            0x00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000ff
            SIGNER_1))

        ;; Second mint with same nonce should fail with ERR_NONCE_PROCESSED (u103)
        (let (
            (result (contract-call? .lux-bridge mint-bridged
                u96369 u1 WALLET_2 u500000
                0x00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000ff
                SIGNER_1))
        )
            (asserts! (is-err result) (err u3200))
            (asserts! (is-eq result (err u103)) (err u3201))
            (ok true))))

;; ============================================================
;; Test: burn-bridged
;; ============================================================

(define-public (test-burn-bridged-ok)
    (let (
        (result (contract-call? .lux-bridge burn-bridged u500000 DEST_CHAIN DUMMY_RECIPIENT))
    )
        (asserts! (is-ok result) (err u4000))
        (asserts! (is-eq (unwrap-panic result) u1) (err u4001))
        (asserts! (> (contract-call? .lux-bridge get-total-burned) u0) (err u4002))
        (ok true)))

(define-public (test-burn-zero-amount)
    (let (
        (result (contract-call? .lux-bridge burn-bridged u0 DEST_CHAIN DUMMY_RECIPIENT))
    )
        (asserts! (is-err result) (err u4100))
        (asserts! (is-eq result (err u105)) (err u4101))
        (ok true)))

;; ============================================================
;; Test: pause / unpause
;; ============================================================

(define-public (test-pause-by-admin)
    (begin
        ;; Admin pauses
        (unwrap-panic (contract-call? .lux-bridge set-paused true))
        (asserts! (is-eq (contract-call? .lux-bridge get-paused) true) (err u5000))

        ;; Lock should fail when paused (ERR_PAUSED = u101)
        (let (
            (result (contract-call? .lux-bridge lock-and-bridge u1000000 DEST_CHAIN DUMMY_RECIPIENT))
        )
            (asserts! (is-err result) (err u5001))
            (asserts! (is-eq result (err u101)) (err u5002)))

        ;; Burn should fail when paused
        (let (
            (result (contract-call? .lux-bridge burn-bridged u500000 DEST_CHAIN DUMMY_RECIPIENT))
        )
            (asserts! (is-err result) (err u5003))
            (asserts! (is-eq result (err u101)) (err u5004)))

        ;; Unpause
        (unwrap-panic (contract-call? .lux-bridge set-paused false))
        (asserts! (is-eq (contract-call? .lux-bridge get-paused) false) (err u5005))

        ;; Lock should succeed after unpause
        (asserts! (is-ok (contract-call? .lux-bridge lock-and-bridge u1000000 DEST_CHAIN DUMMY_RECIPIENT)) (err u5006))
        (ok true)))

;; ============================================================
;; Test: set-fee
;; ============================================================

(define-public (test-set-fee-ok)
    (begin
        ;; Set fee to 100 bps (1%)
        (unwrap-panic (contract-call? .lux-bridge set-fee u100))
        (ok true)))

(define-public (test-set-fee-too-high)
    (let (
        ;; MAX_FEE_BPS is 500, so 501 should fail
        (result (contract-call? .lux-bridge set-fee u501))
    )
        (asserts! (is-err result) (err u6000))
        (asserts! (is-eq result (err u106)) (err u6001))
        (ok true)))

;; ============================================================
;; Test: set-signers
;; ============================================================

(define-public (test-set-signers-ok)
    (begin
        (unwrap-panic (contract-call? .lux-bridge set-signers SIGNER_1 SIGNER_2 SIGNER_3))
        (ok true)))

;; ============================================================
;; Test: nonce tracking read-only
;; ============================================================

(define-public (test-is-nonce-processed-default)
    (begin
        ;; Unprocessed nonce returns false
        (asserts! (is-eq (contract-call? .lux-bridge is-nonce-processed u96369 u999) false) (err u7000))
        (ok true)))
