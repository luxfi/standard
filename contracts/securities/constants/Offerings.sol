// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Lux Partners Limited
pragma solidity ^0.8.24;

import { Topics } from "./Topics.sol";

/// @title Offerings
/// @notice The canonical securities-offering taxonomy. Jurisdiction-agnostic
///         primary types + named aliases for the major jurisdictional
///         exemptions that map onto each type. Country gates are configured
///         per-token on `CountryAllowModule` / `CountryRestrictModule`
///         (T-REX legacy) — not encoded here.
/// @dev    The primary taxonomy is the GENERIC set; the named aliases
///         (`REG_D_506C`, `MAS_S275_AI`, `ASIC_708_SOPH`, etc.) are
///         provided so deployments can reference the locally-recognised
///         name in token metadata. Either form is accepted by
///         `requiredTopics()` because the aliases compute to the same
///         keccak256 as the underlying generic type they map to is up
///         to the issuer's deployment script — both forms coexist.
///
///         Generic primary types:
///           PUBLIC_REGISTERED       Listed, full prospectus / registration.
///                                   US: S-1/S-3. UK: FCA-approved prospectus.
///                                   EU: EU PR. SG: SGX listed. AU: ASX listed.
///                                   CA: provincial-approved prospectus.
///           SMALL_PUBLIC            Mini-IPO / small public offering.
///                                   US: Reg A T1/T2. UK: small-co exemption.
///                                   EU: PR Art 1(3). AU: small-scale.
///           RETAIL_CROWDFUND        Retail crowdfunding with caps.
///                                   US: Reg CF (§4(a)(6)). UK: FCA P2P/Crowdfund.
///                                   EU: ECSP Regulation. AU: CSF.
///           QUALIFIED_PRIVATE       Private placement to qualified investors.
///                                   US: Reg D 506(c) (verified accredited).
///                                   UK: FSMA s86. EU: PR Art 1(4)(a).
///                                   SG: SFA s275 AI. AU: s708(8) sophisticated.
///                                   CA: NI 45-106 AI. UAE: ADGM QI.
///           QUALIFIED_PRIVATE_SELF  Private placement allowing self-attested.
///                                   US: Reg D 506(b). UK: self-cert HNW.
///                                   AU: s708(11) wholesale.
///           SMALL_PRIVATE           Small/limited private placement (<= threshold investors).
///                                   US: Reg D 504. EU: PR Art 1(5)(a) <150 invs.
///                                   UK: Small Co Prospectus exemption.
///                                   AU: s708 20/12mo small-scale.
///           INSTITUTIONAL_ONLY      Institutional-only resale safe harbor.
///                                   US: Rule 144A QIB. EU: MiFID II eligible counterparties.
///                                   SG: SFA s274. JP: FIEL QII.
///           OFFSHORE                Cross-border offshore safe harbor.
///                                   US: Reg S Cat 1/2/3. EU: cross-border via passporting.
///                                   SG: foreign issuer rules. AU: foreign rules.
///           INTRASTATE_LOCAL        Intra-state / intra-jurisdiction offering.
///                                   US: Rule 147/147A. UK: domestic-only.
///                                   AU: state-only. CA: local-jurisdiction.
library Offerings {
    // ── Primary generic taxonomy (jurisdiction-agnostic) ─────────────────
    bytes32 internal constant PUBLIC_REGISTERED       = keccak256("PUBLIC_REGISTERED");
    bytes32 internal constant SMALL_PUBLIC            = keccak256("SMALL_PUBLIC");
    bytes32 internal constant RETAIL_CROWDFUND        = keccak256("RETAIL_CROWDFUND");
    bytes32 internal constant QUALIFIED_PRIVATE       = keccak256("QUALIFIED_PRIVATE");
    bytes32 internal constant QUALIFIED_PRIVATE_SELF  = keccak256("QUALIFIED_PRIVATE_SELF");
    bytes32 internal constant SMALL_PRIVATE           = keccak256("SMALL_PRIVATE");
    bytes32 internal constant INSTITUTIONAL_ONLY      = keccak256("INSTITUTIONAL_ONLY");
    bytes32 internal constant OFFSHORE                = keccak256("OFFSHORE");
    bytes32 internal constant INTRASTATE_LOCAL        = keccak256("INTRASTATE_LOCAL");

    // ── US named aliases ────────────────────────────────────────────────
    bytes32 internal constant RETAIL_PUBLIC = keccak256("RETAIL_PUBLIC"); // legacy alias for PUBLIC_REGISTERED
    bytes32 internal constant FORM_S1       = keccak256("FORM_S1");       // SEC Form S-1 IPO (PUBLIC_REGISTERED)
    bytes32 internal constant FORM_S3       = keccak256("FORM_S3");       // SEC Form S-3 shelf (seasoned issuer)
    bytes32 internal constant FORM_S11      = keccak256("FORM_S11");      // SEC Form S-11 REIT
    bytes32 internal constant FORM_F1       = keccak256("FORM_F1");       // SEC Form F-1 foreign issuer IPO
    bytes32 internal constant REG_A_TIER1   = keccak256("REG_A_TIER1");   // SMALL_PUBLIC, state Blue Sky required
    bytes32 internal constant REG_A_TIER2   = keccak256("REG_A_TIER2");   // SMALL_PUBLIC, federally preempted
    bytes32 internal constant REG_CF        = keccak256("REG_CF");        // RETAIL_CROWDFUND, $5M / 12mo issuer cap
    bytes32 internal constant REG_D_504     = keccak256("REG_D_504");     // SMALL_PRIVATE, $10M / 12mo
    bytes32 internal constant REG_D_506B    = keccak256("REG_D_506B");    // QUALIFIED_PRIVATE_SELF, no gen sol
    bytes32 internal constant REG_D_506C    = keccak256("REG_D_506C");    // QUALIFIED_PRIVATE, gen sol allowed
    bytes32 internal constant REG_S         = keccak256("REG_S");         // OFFSHORE (generic — v1 alias)
    bytes32 internal constant REG_S_CAT1    = keccak256("REG_S_CAT1");    // OFFSHORE, no DCP
    bytes32 internal constant REG_S_CAT2    = keccak256("REG_S_CAT2");    // OFFSHORE, 40-day DCP
    bytes32 internal constant REG_S_CAT3    = keccak256("REG_S_CAT3");    // OFFSHORE, 1-year DCP
    bytes32 internal constant RULE_144A     = keccak256("RULE_144A");     // INSTITUTIONAL_ONLY, QIB resale
    bytes32 internal constant RULE_147      = keccak256("RULE_147");      // INTRASTATE_LOCAL
    bytes32 internal constant RULE_147A     = keccak256("RULE_147A");     // INTRASTATE_LOCAL, allows OOS gen sol

    // ── UK / EU named aliases ───────────────────────────────────────────
    bytes32 internal constant UK_PROSPECTUS         = keccak256("UK_PROSPECTUS");          // PUBLIC_REGISTERED
    bytes32 internal constant UK_FSMA_S86_QI        = keccak256("UK_FSMA_S86_QI");         // QUALIFIED_PRIVATE
    bytes32 internal constant UK_SELF_CERT_HNW      = keccak256("UK_SELF_CERT_HNW");       // QUALIFIED_PRIVATE_SELF
    bytes32 internal constant UK_SMALL_CO           = keccak256("UK_SMALL_CO");            // SMALL_PRIVATE
    bytes32 internal constant UK_FCA_CROWDFUND      = keccak256("UK_FCA_CROWDFUND");       // RETAIL_CROWDFUND
    bytes32 internal constant EU_PROSPECTUS         = keccak256("EU_PROSPECTUS");          // PUBLIC_REGISTERED
    bytes32 internal constant EU_PR_ART1_4_QI       = keccak256("EU_PR_ART1_4_QI");        // QUALIFIED_PRIVATE
    bytes32 internal constant EU_PR_ART1_5_150      = keccak256("EU_PR_ART1_5_150");       // SMALL_PRIVATE (<150 investors)
    bytes32 internal constant EU_ECSP_CROWDFUND     = keccak256("EU_ECSP_CROWDFUND");      // RETAIL_CROWDFUND
    bytes32 internal constant LUX_RAIF              = keccak256("LUX_RAIF");               // QUALIFIED_PRIVATE (well-informed)
    bytes32 internal constant LUX_SIF               = keccak256("LUX_SIF");                // INSTITUTIONAL_ONLY

    // ── Singapore named aliases ─────────────────────────────────────────
    bytes32 internal constant SG_SGX_LISTED         = keccak256("SG_SGX_LISTED");          // PUBLIC_REGISTERED
    bytes32 internal constant SG_SFA_S275_AI        = keccak256("SG_SFA_S275_AI");         // QUALIFIED_PRIVATE
    bytes32 internal constant SG_SFA_S274_II        = keccak256("SG_SFA_S274_II");         // INSTITUTIONAL_ONLY
    bytes32 internal constant SG_SFA_S302_RESTRICTED = keccak256("SG_SFA_S302_RESTRICTED"); // SMALL_PRIVATE

    // ── UAE named aliases ───────────────────────────────────────────────
    bytes32 internal constant UAE_ADGM_QI           = keccak256("UAE_ADGM_QI");            // QUALIFIED_PRIVATE
    bytes32 internal constant UAE_DIFC_PRO          = keccak256("UAE_DIFC_PRO");           // QUALIFIED_PRIVATE
    bytes32 internal constant UAE_DIFC_HNW          = keccak256("UAE_DIFC_HNW");           // QUALIFIED_PRIVATE_SELF

    // ── Australia named aliases ─────────────────────────────────────────
    bytes32 internal constant AU_ASX_LISTED         = keccak256("AU_ASX_LISTED");          // PUBLIC_REGISTERED
    bytes32 internal constant AU_S708_SOPHISTICATED = keccak256("AU_S708_SOPHISTICATED");  // QUALIFIED_PRIVATE
    bytes32 internal constant AU_S708_WHOLESALE     = keccak256("AU_S708_WHOLESALE");      // QUALIFIED_PRIVATE_SELF
    bytes32 internal constant AU_S708_PROFESSIONAL  = keccak256("AU_S708_PROFESSIONAL");   // INSTITUTIONAL_ONLY
    bytes32 internal constant AU_CSF_CROWDFUND      = keccak256("AU_CSF_CROWDFUND");       // RETAIL_CROWDFUND

    // ── Canada named aliases ────────────────────────────────────────────
    bytes32 internal constant CA_TSX_LISTED         = keccak256("CA_TSX_LISTED");          // PUBLIC_REGISTERED
    bytes32 internal constant CA_NI45106_AI         = keccak256("CA_NI45106_AI");          // QUALIFIED_PRIVATE
    bytes32 internal constant CA_NI45106_OM         = keccak256("CA_NI45106_OM");          // SMALL_PRIVATE (offering memo)
    bytes32 internal constant CA_NI45106_FFBA       = keccak256("CA_NI45106_FFBA");        // QUALIFIED_PRIVATE_SELF (friends/family/BA)

    // ── Hong Kong / Japan / Switzerland named aliases ───────────────────
    bytes32 internal constant HK_SFO_PRO            = keccak256("HK_SFO_PRO");             // QUALIFIED_PRIVATE
    bytes32 internal constant JP_FIEL_QII           = keccak256("JP_FIEL_QII");            // INSTITUTIONAL_ONLY
    bytes32 internal constant JP_FIEL_SI            = keccak256("JP_FIEL_SI");             // QUALIFIED_PRIVATE
    bytes32 internal constant CH_FINSA_QI           = keccak256("CH_FINSA_QI");            // QUALIFIED_PRIVATE
    bytes32 internal constant CH_FINSA_INST         = keccak256("CH_FINSA_INST");          // INSTITUTIONAL_ONLY

    /// @notice Resolve any offering identifier (generic or named alias) to
    ///         the underlying generic taxonomy bucket. Returns the same
    ///         input for generic types and the canonical generic identifier
    ///         for named aliases.
    function normalise(bytes32 offering) internal pure returns (bytes32) {
        // US
        if (offering == RETAIL_PUBLIC ||
            offering == FORM_S1 ||
            offering == FORM_S3 ||
            offering == FORM_S11 ||
            offering == FORM_F1) return PUBLIC_REGISTERED;
        if (offering == REG_A_TIER1 || offering == REG_A_TIER2) return SMALL_PUBLIC;
        if (offering == REG_CF) return RETAIL_CROWDFUND;
        if (offering == REG_D_504) return SMALL_PRIVATE;
        if (offering == REG_D_506B) return QUALIFIED_PRIVATE_SELF;
        if (offering == REG_D_506C) return QUALIFIED_PRIVATE;
        if (offering == REG_S || offering == REG_S_CAT1 || offering == REG_S_CAT2 || offering == REG_S_CAT3) return OFFSHORE;
        if (offering == RULE_144A) return INSTITUTIONAL_ONLY;
        if (offering == RULE_147 || offering == RULE_147A) return INTRASTATE_LOCAL;
        // UK / EU
        if (offering == UK_PROSPECTUS || offering == EU_PROSPECTUS) return PUBLIC_REGISTERED;
        if (offering == UK_FSMA_S86_QI || offering == EU_PR_ART1_4_QI || offering == LUX_RAIF) return QUALIFIED_PRIVATE;
        if (offering == UK_SELF_CERT_HNW) return QUALIFIED_PRIVATE_SELF;
        if (offering == UK_SMALL_CO || offering == EU_PR_ART1_5_150) return SMALL_PRIVATE;
        if (offering == UK_FCA_CROWDFUND || offering == EU_ECSP_CROWDFUND) return RETAIL_CROWDFUND;
        if (offering == LUX_SIF) return INSTITUTIONAL_ONLY;
        // Singapore
        if (offering == SG_SGX_LISTED) return PUBLIC_REGISTERED;
        if (offering == SG_SFA_S275_AI) return QUALIFIED_PRIVATE;
        if (offering == SG_SFA_S274_II) return INSTITUTIONAL_ONLY;
        if (offering == SG_SFA_S302_RESTRICTED) return SMALL_PRIVATE;
        // UAE
        if (offering == UAE_ADGM_QI || offering == UAE_DIFC_PRO) return QUALIFIED_PRIVATE;
        if (offering == UAE_DIFC_HNW) return QUALIFIED_PRIVATE_SELF;
        // Australia
        if (offering == AU_ASX_LISTED) return PUBLIC_REGISTERED;
        if (offering == AU_S708_SOPHISTICATED) return QUALIFIED_PRIVATE;
        if (offering == AU_S708_WHOLESALE) return QUALIFIED_PRIVATE_SELF;
        if (offering == AU_S708_PROFESSIONAL) return INSTITUTIONAL_ONLY;
        if (offering == AU_CSF_CROWDFUND) return RETAIL_CROWDFUND;
        // Canada
        if (offering == CA_TSX_LISTED) return PUBLIC_REGISTERED;
        if (offering == CA_NI45106_AI) return QUALIFIED_PRIVATE;
        if (offering == CA_NI45106_OM) return SMALL_PRIVATE;
        if (offering == CA_NI45106_FFBA) return QUALIFIED_PRIVATE_SELF;
        // HK / JP / CH
        if (offering == HK_SFO_PRO || offering == JP_FIEL_SI || offering == CH_FINSA_QI) return QUALIFIED_PRIVATE;
        if (offering == JP_FIEL_QII || offering == CH_FINSA_INST) return INSTITUTIONAL_ONLY;
        // Generic / passthrough
        if (
            offering == PUBLIC_REGISTERED ||
            offering == SMALL_PUBLIC ||
            offering == RETAIL_CROWDFUND ||
            offering == QUALIFIED_PRIVATE ||
            offering == QUALIFIED_PRIVATE_SELF ||
            offering == SMALL_PRIVATE ||
            offering == INSTITUTIONAL_ONLY ||
            offering == OFFSHORE ||
            offering == INTRASTATE_LOCAL
        ) {
            return offering;
        }
        revert UnknownOffering(offering);
    }

    /// @notice Required claim topics for a given offering type. Generic + alias
    ///         both supported (aliases are normalised first).
    /// @dev    Returns the MINIMUM set; per-token modules layer additional
    ///         requirements (e.g. RegCFFirstYearModule adds the topic 105
    ///         REG_CF check at transfer time; OffshoreDistributionPeriodModule
    ///         layers the DCP for OFFSHORE tokens).
    function requiredTopics(bytes32 offering) internal pure returns (uint256[] memory topics) {
        bytes32 t = normalise(offering);

        if (t == PUBLIC_REGISTERED) {
            topics = new uint256[](2);
            topics[0] = Topics.KYC;
            topics[1] = Topics.AML;
        } else if (t == SMALL_PUBLIC || t == RETAIL_CROWDFUND || t == SMALL_PRIVATE) {
            // Caps are off-chain; the on-chain gate just needs identity.
            topics = new uint256[](2);
            topics[0] = Topics.KYC;
            topics[1] = Topics.AML;
        } else if (t == QUALIFIED_PRIVATE_SELF) {
            topics = new uint256[](3);
            topics[0] = Topics.KYC;
            topics[1] = Topics.AML;
            topics[2] = Topics.ACCREDITED_SELF;
        } else if (t == QUALIFIED_PRIVATE) {
            topics = new uint256[](3);
            topics[0] = Topics.KYC;
            topics[1] = Topics.AML;
            topics[2] = Topics.ACCREDITED_VERIFIED;
        } else if (t == INSTITUTIONAL_ONLY) {
            topics = new uint256[](3);
            topics[0] = Topics.KYC;
            topics[1] = Topics.AML;
            topics[2] = Topics.QIB;
        } else if (t == OFFSHORE) {
            topics = new uint256[](3);
            topics[0] = Topics.KYC;
            topics[1] = Topics.AML;
            topics[2] = Topics.JURISDICTION;
        } else if (t == INTRASTATE_LOCAL) {
            // KYC + AML + state-match enforced by BlueSkyStateModule against
            // per-token home-state claim (topic 106 BLUE_SKY_STATE).
            topics = new uint256[](3);
            topics[0] = Topics.KYC;
            topics[1] = Topics.AML;
            topics[2] = Topics.JURISDICTION;
        } else {
            revert UnknownOffering(offering);
        }
    }

    error UnknownOffering(bytes32 offering);
}
