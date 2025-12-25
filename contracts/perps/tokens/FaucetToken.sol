// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * @title FaucetToken
 * @notice ERC20 token with faucet functionality for testnets
 * @dev Extends OZ 5.x ERC20 with drip/claim mechanics
 */
contract FaucetToken is ERC20 {
    uint256 public constant DROPLET_INTERVAL = 8 hours;

    address public gov;
    uint256 public dropletAmount;
    bool public isFaucetEnabled;
    uint8 private immutable _tokenDecimals;

    mapping(address => uint256) public claimedAt;

    modifier onlyGov() {
        require(msg.sender == gov, "FaucetToken: forbidden");
        _;
    }

    constructor(
        string memory name_,
        string memory symbol_,
        uint8 decimals_,
        uint256 dropletAmount_
    ) ERC20(name_, symbol_) {
        gov = msg.sender;
        dropletAmount = dropletAmount_;
        _tokenDecimals = decimals_;
    }

    function decimals() public view virtual override returns (uint8) {
        return _tokenDecimals;
    }

    /**
     * @notice Mint tokens (gov only)
     * @param account Recipient address
     * @param amount Amount to mint
     */
    function mint(address account, uint256 amount) public onlyGov {
        _mint(account, amount);
    }

    /**
     * @notice Enable the faucet (gov only)
     */
    function enableFaucet() public onlyGov {
        isFaucetEnabled = true;
    }

    /**
     * @notice Disable the faucet (gov only)
     */
    function disableFaucet() public onlyGov {
        isFaucetEnabled = false;
    }

    /**
     * @notice Set the droplet amount (gov only)
     * @param dropletAmount_ New droplet amount
     */
    function setDropletAmount(uint256 dropletAmount_) public onlyGov {
        dropletAmount = dropletAmount_;
    }

    /**
     * @notice Claim tokens from the faucet
     * @dev Rate-limited to once per DROPLET_INTERVAL
     */
    function claimDroplet() public {
        require(isFaucetEnabled, "FaucetToken: faucet not enabled");
        require(
            claimedAt[msg.sender] + DROPLET_INTERVAL <= block.timestamp,
            "FaucetToken: droplet not available yet"
        );
        claimedAt[msg.sender] = block.timestamp;
        _mint(msg.sender, dropletAmount);
    }
}
