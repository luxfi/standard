// Copyright (C) 2019-2025, Lux Industries, Inc. All rights reserved.
// See the file LICENSE for licensing terms.

package warp

import (
	"fmt"
	"math"

	"github.com/luxfi/evm/precompile/contract"
	"github.com/luxfi/evm/predicate"
	"github.com/luxfi/geth/common"
	commonmath "github.com/luxfi/geth/common/math"
	"github.com/luxfi/geth/core/vm"
	"github.com/luxfi/math/set"
	"github.com/luxfi/warp"
	"github.com/luxfi/warp/payload"
)

var (
	_ messageHandler = addressedPayloadHandler{}
	_ messageHandler = blockHashHandler{}
)

var (
	getVerifiedWarpMessageInvalidOutput   []byte
	getVerifiedWarpBlockHashInvalidOutput []byte
)

func init() {
	res, err := PackGetVerifiedWarpMessageOutput(GetVerifiedWarpMessageOutput{Valid: false})
	if err != nil {
		panic(err)
	}
	getVerifiedWarpMessageInvalidOutput = res

	res, err = PackGetVerifiedWarpBlockHashOutput(GetVerifiedWarpBlockHashOutput{Valid: false})
	if err != nil {
		panic(err)
	}
	getVerifiedWarpBlockHashInvalidOutput = res
}

type messageHandler interface {
	packFailed() []byte
	handleMessage(msg *warp.Message) ([]byte, error)
}

func handleWarpMessage(accessibleState contract.AccessibleState, input []byte, suppliedGas uint64, handler messageHandler) ([]byte, uint64, error) {
	remainingGas, err := contract.DeductGas(suppliedGas, GetVerifiedWarpMessageBaseCost)
	if err != nil {
		return nil, remainingGas, err
	}

	warpIndexInput, err := UnpackGetVerifiedWarpMessageInput(input)
	if err != nil {
		return nil, remainingGas, fmt.Errorf("%w: %s", errInvalidIndexInput, err)
	}
	if warpIndexInput > math.MaxInt32 {
		return nil, remainingGas, fmt.Errorf("%w: larger than MaxInt32", errInvalidIndexInput)
	}
	warpIndex := int(warpIndexInput) // This conversion is safe even if int is 32 bits because we checked above.
	state := accessibleState.GetStateDB()
	predicateBytes, exists := state.GetPredicateStorageSlots(ContractAddress, warpIndex)
	predicateResults := accessibleState.GetBlockContext().GetPredicateResults(state.GetTxHash(), ContractAddress)
	valid := exists && !set.BitsFromBytes(predicateResults).Contains(warpIndex)
	if !valid {
		return handler.packFailed(), remainingGas, nil
	}

	// Note: we charge for the size of the message during both predicate verification and each time the message is read during
	// EVM execution because each execution incurs an additional read cost.
	msgBytesGas, overflow := commonmath.SafeMul(GasCostPerWarpMessageBytes, uint64(len(predicateBytes)))
	if overflow {
		return nil, 0, vm.ErrOutOfGas
	}
	if remainingGas, err = contract.DeductGas(remainingGas, msgBytesGas); err != nil {
		return nil, 0, err
	}
	// Note: since the predicate is verified in advance of execution, the precompile should not
	// hit an error during execution.
	unpackedPredicateBytes, err := predicate.UnpackPredicate(predicateBytes)
	if err != nil {
		return nil, remainingGas, fmt.Errorf("%w: %s", errInvalidPredicateBytes, err)
	}
	warpMessage, err := warp.ParseMessage(unpackedPredicateBytes)
	if err != nil {
		return nil, remainingGas, fmt.Errorf("%w: %s", errInvalidWarpMsg, err)
	}
	res, err := handler.handleMessage(warpMessage)
	if err != nil {
		return nil, remainingGas, err
	}
	return res, remainingGas, nil
}

type addressedPayloadHandler struct{}

func (addressedPayloadHandler) packFailed() []byte {
	return getVerifiedWarpMessageInvalidOutput
}

func (addressedPayloadHandler) handleMessage(warpMessage *warp.Message) ([]byte, error) {
	addressedPayload, err := payload.Parse(warpMessage.UnsignedMessage.Payload)
	if err != nil {
		return nil, fmt.Errorf("%w: %s", errInvalidAddressedPayload, err)
	}
	// Type assert to AddressedCall
	addressedCall, ok := addressedPayload.(*payload.AddressedCall)
	if !ok {
		return nil, fmt.Errorf("%w: payload is not AddressedCall", errInvalidAddressedPayload)
	}
	return PackGetVerifiedWarpMessageOutput(GetVerifiedWarpMessageOutput{
		Message: WarpMessage{
			SourceChainID:       common.BytesToHash(warpMessage.UnsignedMessage.SourceChainID[:]),
			OriginSenderAddress: common.BytesToAddress(addressedCall.SourceAddress),
			Payload:             addressedCall.Payload,
		},
		Valid: true,
	})
}

type blockHashHandler struct{}

func (blockHashHandler) packFailed() []byte {
	return getVerifiedWarpBlockHashInvalidOutput
}

func (blockHashHandler) handleMessage(warpMessage *warp.Message) ([]byte, error) {
	parsedPayload, err := payload.Parse(warpMessage.UnsignedMessage.Payload)
	if err != nil {
		return nil, fmt.Errorf("%w: %s", errInvalidBlockHashPayload, err)
	}
	// Type assert to Hash
	blockHashPayload, ok := parsedPayload.(*payload.Hash)
	if !ok {
		return nil, fmt.Errorf("%w: payload is not Hash", errInvalidBlockHashPayload)
	}
	return PackGetVerifiedWarpBlockHashOutput(GetVerifiedWarpBlockHashOutput{
		WarpBlockHash: WarpBlockHash{
			SourceChainID: common.BytesToHash(warpMessage.UnsignedMessage.SourceChainID[:]),
			BlockHash:     common.BytesToHash(blockHashPayload.Hash[:]),
		},
		Valid: true,
	})
}
