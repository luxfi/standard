// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.30;

import {IAvatar} from "../interfaces/dao/IAvatar.sol";
import {Enum} from "./safe-smart-account/common/Enum.sol";

contract MockAvatar is IAvatar {
    mapping(address => address) internal modules;
    address internal constant SENTINEL_MODULES = address(0x1);

    constructor() {
        modules[SENTINEL_MODULES] = SENTINEL_MODULES;
    }

    function enableModule(address _module) external override {
        require(
            _module != address(0) && _module != SENTINEL_MODULES,
            "Invalid module"
        );
        require(modules[_module] == address(0), "Module already enabled");
        modules[_module] = modules[SENTINEL_MODULES];
        modules[SENTINEL_MODULES] = _module;
    }

    function disableModule(
        address prevModule,
        address _module
    ) external override {
        require(
            _module != address(0) && _module != SENTINEL_MODULES,
            "Invalid module"
        );
        require(modules[prevModule] == _module, "Invalid module pair");
        modules[prevModule] = modules[_module];
        modules[_module] = address(0);
    }

    function isModuleEnabled(
        address _module
    ) external view override returns (bool) {
        return SENTINEL_MODULES != _module && modules[_module] != address(0);
    }

    function getModulesPaginated(
        address start,
        uint256 pageSize
    ) external view override returns (address[] memory array, address next) {
        array = new address[](pageSize);
        uint256 moduleCount = 0;
        address currentModule = modules[start];
        while (
            currentModule != address(0x0) &&
            currentModule != SENTINEL_MODULES &&
            moduleCount < pageSize
        ) {
            array[moduleCount] = currentModule;
            currentModule = modules[currentModule];
            moduleCount++;
        }
        next = currentModule;
        assembly {
            mstore(array, moduleCount)
        }
    }

    function execTransactionFromModule(
        address to,
        uint256 value,
        bytes calldata data,
        Enum.Operation operation
    ) external override returns (bool success) {
        require(modules[msg.sender] != address(0), "Not authorized");

        if (operation == Enum.Operation.Call) {
            (success, ) = to.call{value: value}(data);
        } else {
            (success, ) = to.delegatecall(data);
        }
    }

    function execTransactionFromModuleReturnData(
        address to,
        uint256 value,
        bytes calldata data,
        Enum.Operation operation
    ) external override returns (bool success, bytes memory returnData) {
        require(modules[msg.sender] != address(0), "Not authorized");

        if (operation == Enum.Operation.Call) {
            (success, returnData) = to.call{value: value}(data);
        } else {
            (success, returnData) = to.delegatecall(data);
        }
    }

    receive() external payable {}
}
