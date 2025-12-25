// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

/**
 * ╔═══════════════════════════════════════════════════════════════════════════════╗
 * ║                          CAPITAL OS - CORE PRIMITIVES                         ║
 * ╠═══════════════════════════════════════════════════════════════════════════════╣
 * ║  This is not a protocol zoo. This is a unified Capital Operating System.      ║
 * ║                                                                               ║
 * ║  Every DeFi protocol reduces to combinations of these 6 primitives:           ║
 * ║                                                                               ║
 * ║  1. CAPITAL      - Where does value originate?                               ║
 * ║  2. YIELD        - How does capital grow?                                    ║
 * ║  3. OBLIGATION   - What is owed? (THE theological/regulatory line)           ║
 * ║  4. SETTLEMENT   - How are obligations fulfilled?                            ║
 * ║  5. RISK         - What happens when assumptions break?                      ║
 * ║  6. DISTRIBUTION - Who receives yield?                                       ║
 * ║                                                                               ║
 * ╠═══════════════════════════════════════════════════════════════════════════════╣
 * ║                          THE CORE LOOP                                        ║
 * ╠═══════════════════════════════════════════════════════════════════════════════╣
 * ║                                                                               ║
 * ║    Capital → produces → Yield → settles → Obligations → unlocks → Capital    ║
 * ║                                                                               ║
 * ║  That loop IS your bank.                                                     ║
 * ║                                                                               ║
 * ╠═══════════════════════════════════════════════════════════════════════════════╣
 * ║                     PROTOCOL → PRIMITIVE MAPPING                              ║
 * ╠═══════════════════════════════════════════════════════════════════════════════╣
 * ║                                                                               ║
 * ║  Compound  = Capital + Yield(Interest) + Obligation(INCREASING) + Risk       ║
 * ║  GMX       = Capital + Yield(Fees) + Risk + Distribution                     ║
 * ║  Alchemix  = Capital + Yield(Strategy) + Obligation(DECREASING) + Settlement ║
 * ║  Maple     = Capital + Yield(RWA) + Obligation(INCREASING)                   ║
 * ║  Olympus   = Capital + Yield(Revenue) + Distribution(Rebasing)               ║
 * ║                                                                               ║
 * ╠═══════════════════════════════════════════════════════════════════════════════╣
 * ║                      SHARIAH COMPLIANCE LINE                                  ║
 * ╠═══════════════════════════════════════════════════════════════════════════════╣
 * ║                                                                               ║
 * ║  INCREASING obligation = riba (interest) = NOT Shariah-compliant             ║
 * ║  DECREASING obligation = self-repaying   = Shariah-compliant                 ║
 * ║                                                                               ║
 * ║  This distinction enables:                                                   ║
 * ║    • Self-repaying credit cards                                              ║
 * ║    • Ethical finance for the unbanked                                        ║
 * ║    • Islamic banking compatibility                                           ║
 * ║    • No debt spirals by construction                                         ║
 * ║                                                                               ║
 * ╚═══════════════════════════════════════════════════════════════════════════════╝
 */

// Core Primitive Interfaces
import {ICapital, RiskTier, CapitalState} from "./ICapital.sol";
import {IYield, YieldType, AccrualPattern} from "./IYield.sol";
import {IObligation, Monotonicity, ObligationState, ObligationLib} from "./IObligation.sol";
import {ISettlement, SettlementType, SettlementState, SettlementLib} from "./ISettlement.sol";
import {IRisk, InterventionType, HealthStatus, RiskLib} from "./IRisk.sol";
import {IDistribution, DistributionType, RecipientClass, DistributionLib} from "./IDistribution.sol";
