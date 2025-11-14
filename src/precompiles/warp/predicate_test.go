// Copyright (C) 2019-2025, Lux Industries, Inc. All rights reserved.
// See the file LICENSE for licensing terms.

package warp

import (
	"context"
	"errors"
	"fmt"
	"testing"

	"github.com/luxfi/consensus"
	"github.com/luxfi/consensus/engine/chain/block"
	"github.com/luxfi/consensus/validator"
	"github.com/luxfi/consensus/validator/validatorstest"
	"github.com/luxfi/crypto/bls"
	"github.com/luxfi/crypto/bls/signer/localsigner"
	"github.com/luxfi/evm/precompile/precompileconfig"
	"github.com/luxfi/evm/precompile/precompiletest"
	"github.com/luxfi/evm/predicate"
	"github.com/luxfi/evm/utils"
	"github.com/luxfi/evm/utils/utilstest"
	"github.com/luxfi/ids"
	agoUtils "github.com/luxfi/node/utils"
	"github.com/luxfi/node/utils/constants"
	luxWarp "github.com/luxfi/warp"
	warpBls "github.com/luxfi/warp/bls"
	"github.com/luxfi/warp/payload"
	"github.com/stretchr/testify/require"
)

const pChainHeight uint64 = 1337

// convertWarpToCryptoPublicKey converts a warp/bls.PublicKey to crypto/bls.PublicKey
func convertWarpToCryptoPublicKey(warpPK *warpBls.PublicKey) (*bls.PublicKey, error) {
	if warpPK == nil {
		return nil, nil
	}
	// Convert the warp public key bytes to crypto public key
	warpBytes := warpBls.PublicKeyToBytes(warpPK)
	return bls.PublicKeyFromCompressedBytes(warpBytes)
}

// convertCryptoToWarpPublicKey converts a crypto/bls.PublicKey to warp/bls.PublicKey
func convertCryptoToWarpPublicKey(cryptoPK *bls.PublicKey) (*warpBls.PublicKey, error) {
	if cryptoPK == nil {
		return nil, nil
	}
	// Convert the crypto public key bytes to warp public key
	cryptoBytes := bls.PublicKeyToCompressedBytes(cryptoPK)
	return warpBls.PublicKeyFromBytes(cryptoBytes)
}

var (
	_ agoUtils.Sortable[*testValidator] = (*testValidator)(nil)

	errTest        = errors.New("non-nil error")
	sourceChainID  = ids.GenerateTestID()
	sourceSubnetID = ids.GenerateTestID()

	// valid unsigned warp message used throughout testing
	unsignedMsg *luxWarp.UnsignedMessage
	// valid addressed payload
	addressedPayload      *payload.AddressedCall
	addressedPayloadBytes []byte
	// blsSignatures of [unsignedMsg] from each of [testVdrs]
	blsSignatures []*bls.Signature

	numTestVdrs = 10_000
	testVdrs    []*testValidator
	vdrs        map[ids.NodeID]*validators.GetValidatorOutput
)

func init() {
	testVdrs = make([]*testValidator, 0, numTestVdrs)
	for i := 0; i < numTestVdrs; i++ {
		testVdrs = append(testVdrs, newTestValidator())
	}
	agoUtils.Sort(testVdrs)

	vdrs = map[ids.NodeID]*validators.GetValidatorOutput{
		testVdrs[0].nodeID: {
			NodeID:    testVdrs[0].nodeID,
			PublicKey: bls.PublicKeyToCompressedBytes(testVdrs[0].cryptoPK),
			Weight:    testVdrs[0].vdr.Weight,
		},
		testVdrs[1].nodeID: {
			NodeID:    testVdrs[1].nodeID,
			PublicKey: bls.PublicKeyToCompressedBytes(testVdrs[1].cryptoPK),
			Weight:    testVdrs[1].vdr.Weight,
		},
		testVdrs[2].nodeID: {
			NodeID:    testVdrs[2].nodeID,
			PublicKey: bls.PublicKeyToCompressedBytes(testVdrs[2].cryptoPK),
			Weight:    testVdrs[2].vdr.Weight,
		},
	}

	var err error
	addr := ids.GenerateTestShortID()
	addressedPayload, err = payload.NewAddressedCall(
		addr[:],
		[]byte{1, 2, 3},
	)
	if err != nil {
		panic(err)
	}
	addressedPayloadBytes = addressedPayload.Bytes()
	unsignedMsg, err = luxWarp.NewUnsignedMessage(constants.UnitTestID, sourceChainID[:], addressedPayload.Bytes())
	if err != nil {
		panic(err)
	}

	for _, testVdr := range testVdrs {
		blsSignature, err := testVdr.sk.Sign(unsignedMsg.Bytes())
		if err != nil {
			panic(err)
		}
		blsSignatures = append(blsSignatures, blsSignature)
	}
}

type testValidator struct {
	nodeID   ids.NodeID
	sk       bls.Signer
	vdr      *luxWarp.Validator
	cryptoPK *bls.PublicKey // Cached crypto/bls public key for consensus validation
}

func (v *testValidator) Compare(o *testValidator) int {
	// Compare by public key bytes since warp.Validator doesn't have Compare method
	if v.vdr.Less(o.vdr) {
		return -1
	}
	if o.vdr.Less(v.vdr) {
		return 1
	}
	return 0
}

func newTestValidator() *testValidator {
	sk, err := localsigner.New()
	if err != nil {
		panic(err)
	}

	nodeID := ids.GenerateTestNodeID()
	cryptoPK := sk.PublicKey()
	cryptoPKBytes := bls.PublicKeyToCompressedBytes(cryptoPK)

	// Convert crypto public key to warp public key
	warpPK, err := convertCryptoToWarpPublicKey(cryptoPK)
	if err != nil {
		panic(err)
	}

	return &testValidator{
		nodeID:   nodeID,
		sk:       sk,
		cryptoPK: cryptoPK,
		vdr: &luxWarp.Validator{
			PublicKey:      warpPK,
			PublicKeyBytes: cryptoPKBytes, // Use the same bytes from crypto
			Weight:         3,
			NodeID:         nodeID[:],
		},
	}
}

// createWarpMessage constructs a signed warp message using the global variable [unsignedMsg]
// and the first [numKeys] signatures from [blsSignatures]
func createWarpMessage(numKeys int) *luxWarp.Message {
	aggregateSignature, err := bls.AggregateSignatures(blsSignatures[0:numKeys])
	if err != nil {
		panic(err)
	}
	bitSet := luxWarp.NewBitSet()
	for i := 0; i < numKeys; i++ {
		bitSet.Add(i)
	}
	warpSignature := &luxWarp.BitSetSignature{
		Signers: bitSet,
	}
	copy(warpSignature.Signature[:], bls.SignatureToBytes(aggregateSignature))

	// Create a simplified Message structure for testing
	// Since the warp package has interface serialization issues,
	// we'll create a mock message that contains the necessary data
	warpMsg := &luxWarp.Message{
		UnsignedMessage: unsignedMsg,
		Signature:       warpSignature,
	}
	return warpMsg
}

// createPredicate constructs a warp message using createWarpMessage with numKeys signers
// and packs it into predicate encoding.
func createPredicate(numKeys int) []byte {
	warpMsg := createWarpMessage(numKeys)
	predicateBytes := predicate.PackPredicate(warpMsg.Bytes())
	return predicateBytes
}

// validatorRange specifies a range of validators to include from [start, end), a staking weight
// to specify for each validator in that range, and whether or not to include the public key.
type validatorRange struct {
	start     int
	end       int
	weight    uint64
	publicKey bool
}

// testValidatorStateWrapper wraps validatorstest.State to implement consensus.ValidatorState
type testValidatorStateWrapper struct {
	*validatorstest.State
	GetMinimumHeightF func(context.Context) (uint64, error)
	GetSubnetIDF      func(ids.ID) (ids.ID, error)
	GetChainIDF       func(ids.ID) (ids.ID, error)
	GetNetIDF         func(ids.ID) (ids.ID, error)
}

func (t *testValidatorStateWrapper) GetCurrentHeight() (uint64, error) {
	return t.State.GetCurrentHeight(context.Background())
}

func (t *testValidatorStateWrapper) GetMinimumHeight(ctx context.Context) (uint64, error) {
	if t.GetMinimumHeightF != nil {
		return t.GetMinimumHeightF(ctx)
	}
	return 0, nil
}

func (t *testValidatorStateWrapper) GetValidatorSet(height uint64, subnetID ids.ID) (map[ids.NodeID]uint64, error) {
	validators, err := t.State.GetValidatorSet(context.Background(), height, subnetID)
	if err != nil {
		return nil, err
	}
	result := make(map[ids.NodeID]uint64, len(validators))
	for nodeID, output := range validators {
		result[nodeID] = output.Weight
	}
	return result, nil
}

func (t *testValidatorStateWrapper) GetSubnetID(chainID ids.ID) (ids.ID, error) {
	if t.GetSubnetIDF != nil {
		return t.GetSubnetIDF(chainID)
	}
	return ids.Empty, nil
}

func (t *testValidatorStateWrapper) GetChainID(subnetID ids.ID) (ids.ID, error) {
	if t.GetChainIDF != nil {
		return t.GetChainIDF(subnetID)
	}
	return ids.Empty, nil
}

func (t *testValidatorStateWrapper) GetNetID(chainID ids.ID) (ids.ID, error) {
	if t.GetNetIDF != nil {
		return t.GetNetIDF(chainID)
	}
	return ids.Empty, nil
}

// createConsensusCtx creates a context.Context instance with a validator state specified by the given validatorRanges
func createConsensusCtx(tb testing.TB, validatorRanges []validatorRange) context.Context {
	getValidatorsOutput := make(map[ids.NodeID]*validators.GetValidatorOutput)

	for _, validatorRange := range validatorRanges {
		for i := validatorRange.start; i < validatorRange.end; i++ {
			validatorOutput := &validators.GetValidatorOutput{
				NodeID: testVdrs[i].nodeID,
				Weight: validatorRange.weight,
			}
			if validatorRange.publicKey {
				validatorOutput.PublicKey = bls.PublicKeyToCompressedBytes(testVdrs[i].cryptoPK)
			}
			getValidatorsOutput[testVdrs[i].nodeID] = validatorOutput
		}
	}

	consensusCtx := utilstest.NewTestConsensusContext(tb)
	state := &validatorstest.State{
		GetValidatorSetF: func(ctx context.Context, height uint64, subnetID ids.ID) (map[ids.NodeID]*validators.GetValidatorOutput, error) {
			return getValidatorsOutput, nil
		},
	}
	// Use consensus.WithValidatorState to add validator state to context
	wrappedState := &testValidatorStateWrapper{
		State: state,
		GetSubnetIDF: func(chainID ids.ID) (ids.ID, error) {
			return sourceSubnetID, nil
		},
	}
	consensusCtx = consensus.WithValidatorState(consensusCtx, wrappedState)
	return consensusCtx
}

func createValidPredicateTest(consensusCtx context.Context, numKeys uint64, predicateBytes []byte) precompiletest.PredicateTest {
	return precompiletest.PredicateTest{
		Config: NewDefaultConfig(utils.NewUint64(0)),
		PredicateContext: &precompileconfig.PredicateContext{
			ConsensusCtx: consensusCtx,
			ProposerVMBlockCtx: &block.Context{
				PChainHeight: 1,
			},
		},
		PredicateBytes: predicateBytes,
		Gas:            GasCostPerSignatureVerification + uint64(len(predicateBytes))*GasCostPerWarpMessageBytes + numKeys*GasCostPerWarpSigner,
		GasErr:         nil,
		ExpectedErr:    nil,
	}
}

func TestWarpMessageFromPrimaryNetwork(t *testing.T) {
	for _, requirePrimaryNetworkSigners := range []bool{true, false} {
		testWarpMessageFromPrimaryNetwork(t, requirePrimaryNetworkSigners)
	}
}

func testWarpMessageFromPrimaryNetwork(t *testing.T, requirePrimaryNetworkSigners bool) {
	require := require.New(t)
	numKeys := 10
	cChainID := ids.GenerateTestID()
	addressedCall, err := payload.NewAddressedCall(agoUtils.RandomBytes(20), agoUtils.RandomBytes(100))
	require.NoError(err)
	unsignedMsg, err := luxWarp.NewUnsignedMessage(constants.UnitTestID, cChainID[:], addressedCall.Bytes())
	require.NoError(err)

	getValidatorsOutput := make(map[ids.NodeID]*validators.GetValidatorOutput)
	blsSignatures := make([]*bls.Signature, 0, numKeys)
	for i := 0; i < numKeys; i++ {
		sig, err := testVdrs[i].sk.Sign(unsignedMsg.Bytes())
		require.NoError(err)

		validatorOutput := &validators.GetValidatorOutput{
			NodeID:    testVdrs[i].nodeID,
			Weight:    20,
			PublicKey: bls.PublicKeyToCompressedBytes(testVdrs[i].cryptoPK),
		}
		getValidatorsOutput[testVdrs[i].nodeID] = validatorOutput
		blsSignatures = append(blsSignatures, sig)
	}
	aggregateSignature, err := bls.AggregateSignatures(blsSignatures)
	require.NoError(err)
	bitSet := luxWarp.NewBitSet()
	for i := 0; i < numKeys; i++ {
		bitSet.Add(i)
	}
	warpSignature := &luxWarp.BitSetSignature{
		Signers: bitSet,
	}
	copy(warpSignature.Signature[:], bls.SignatureToBytes(aggregateSignature))
	warpMsg := &luxWarp.Message{
		UnsignedMessage: unsignedMsg,
		Signature:       warpSignature,
	}

	predicateBytes := predicate.PackPredicate(warpMsg.Bytes())

	consensusCtx := utilstest.NewTestConsensusContext(t)
	subnetID := ids.GenerateTestID()
	chainID := ids.GenerateTestID()
	// Use consensus helper functions to add values to context
	consensusCtx = consensus.WithIDs(consensusCtx, consensus.IDs{
		NetworkID: 1,
		NetID:     subnetID,
		ChainID:   chainID,
	})

	state := &validatorstest.State{
		GetValidatorSetF: func(ctx context.Context, height uint64, requestedSubnetID ids.ID) (map[ids.NodeID]*validators.GetValidatorOutput, error) {
			expectedSubnetID := subnetID
			if requirePrimaryNetworkSigners {
				expectedSubnetID = constants.PrimaryNetworkID
			}
			require.Equal(expectedSubnetID, requestedSubnetID)
			return getValidatorsOutput, nil
		},
	}

	// Add validator state to context (wrap it first)
	wrappedState := &testValidatorStateWrapper{
		State: state,
		GetSubnetIDF: func(chainID ids.ID) (ids.ID, error) {
			require.Equal(chainID, cChainID)
			return constants.PrimaryNetworkID, nil // Return Primary Network SubnetID
		},
	}
	consensusCtx = consensus.WithValidatorState(consensusCtx, wrappedState)

	test := precompiletest.PredicateTest{
		Config: NewConfig(utils.NewUint64(0), 0, requirePrimaryNetworkSigners),
		PredicateContext: &precompileconfig.PredicateContext{
			ConsensusCtx: consensusCtx,
			ProposerVMBlockCtx: &block.Context{
				PChainHeight: 1,
			},
		},
		PredicateBytes: predicateBytes,
		Gas:            GasCostPerSignatureVerification + uint64(len(predicateBytes))*GasCostPerWarpMessageBytes + uint64(numKeys)*GasCostPerWarpSigner,
		GasErr:         nil,
		ExpectedErr:    nil,
	}

	test.Run(t)
}

func TestInvalidPredicatePacking(t *testing.T) {
	numKeys := 1
	consensusCtx := createConsensusCtx(t, []validatorRange{
		{
			start:     0,
			end:       numKeys,
			weight:    20,
			publicKey: true,
		},
	})
	predicateBytes := createPredicate(numKeys)
	predicateBytes = append(predicateBytes, byte(0x01)) // Invalidate the predicate byte packing

	test := precompiletest.PredicateTest{
		Config: NewDefaultConfig(utils.NewUint64(0)),
		PredicateContext: &precompileconfig.PredicateContext{
			ConsensusCtx: consensusCtx,
			ProposerVMBlockCtx: &block.Context{
				PChainHeight: 1,
			},
		},
		PredicateBytes: predicateBytes,
		Gas:            GasCostPerSignatureVerification + uint64(len(predicateBytes))*GasCostPerWarpMessageBytes + uint64(numKeys)*GasCostPerWarpSigner,
		GasErr:         errInvalidPredicateBytes,
	}

	test.Run(t)
}

func TestInvalidWarpMessage(t *testing.T) {
	numKeys := 1
	consensusCtx := createConsensusCtx(t, []validatorRange{
		{
			start:     0,
			end:       numKeys,
			weight:    20,
			publicKey: true,
		},
	})
	warpMsg := createWarpMessage(1)
	warpMsgBytes := warpMsg.Bytes()
	warpMsgBytes = append(warpMsgBytes, byte(0x01)) // Invalidate warp message packing
	predicateBytes := predicate.PackPredicate(warpMsgBytes)

	test := precompiletest.PredicateTest{
		Config: NewDefaultConfig(utils.NewUint64(0)),
		PredicateContext: &precompileconfig.PredicateContext{
			ConsensusCtx: consensusCtx,
			ProposerVMBlockCtx: &block.Context{
				PChainHeight: 1,
			},
		},
		PredicateBytes: predicateBytes,
		Gas:            GasCostPerSignatureVerification + uint64(len(predicateBytes))*GasCostPerWarpMessageBytes + uint64(numKeys)*GasCostPerWarpSigner,
		GasErr:         errInvalidWarpMsg,
	}

	test.Run(t)
}

func TestInvalidAddressedPayload(t *testing.T) {
	numKeys := 1
	consensusCtx := createConsensusCtx(t, []validatorRange{
		{
			start:     0,
			end:       numKeys,
			weight:    20,
			publicKey: true,
		},
	})
	aggregateSignature, err := bls.AggregateSignatures(blsSignatures[0:numKeys])
	require.NoError(t, err)
	bitSet := luxWarp.NewBitSet()
	for i := 0; i < numKeys; i++ {
		bitSet.Add(i)
	}
	warpSignature := &luxWarp.BitSetSignature{
		Signers: bitSet,
	}
	copy(warpSignature.Signature[:], bls.SignatureToBytes(aggregateSignature))
	// Create an unsigned message with an invalid addressed payload
	unsignedMsg, err := luxWarp.NewUnsignedMessage(constants.UnitTestID, sourceChainID[:], []byte{1, 2, 3})
	require.NoError(t, err)
	warpMsg := &luxWarp.Message{
		UnsignedMessage: unsignedMsg,
		Signature:       warpSignature,
	}
	warpMsgBytes := warpMsg.Bytes()
	predicateBytes := predicate.PackPredicate(warpMsgBytes)

	test := precompiletest.PredicateTest{
		Config: NewDefaultConfig(utils.NewUint64(0)),
		PredicateContext: &precompileconfig.PredicateContext{
			ConsensusCtx: consensusCtx,
			ProposerVMBlockCtx: &block.Context{
				PChainHeight: 1,
			},
		},
		PredicateBytes: predicateBytes,
		Gas:            GasCostPerSignatureVerification + uint64(len(predicateBytes))*GasCostPerWarpMessageBytes + uint64(numKeys)*GasCostPerWarpSigner,
		GasErr:         errInvalidWarpMsgPayload,
	}

	test.Run(t)
}

func TestInvalidBitSet(t *testing.T) {
	addressedCall, err := payload.NewAddressedCall(agoUtils.RandomBytes(20), agoUtils.RandomBytes(100))
	require.NoError(t, err)
	unsignedMsg, err := luxWarp.NewUnsignedMessage(
		constants.UnitTestID,
		sourceChainID[:],
		addressedCall.Bytes(),
	)
	require.NoError(t, err)

	msg := &luxWarp.Message{
		UnsignedMessage: unsignedMsg,
		Signature: &luxWarp.BitSetSignature{
			Signers:   make([]byte, 1),
			Signature: [warpBls.SignatureLen]byte{},
		},
	}

	numKeys := 1
	consensusCtx := createConsensusCtx(t, []validatorRange{
		{
			start:     0,
			end:       numKeys,
			weight:    20,
			publicKey: true,
		},
	})
	predicateBytes := predicate.PackPredicate(msg.Bytes())
	test := precompiletest.PredicateTest{
		Config: NewDefaultConfig(utils.NewUint64(0)),
		PredicateContext: &precompileconfig.PredicateContext{
			ConsensusCtx: consensusCtx,
			ProposerVMBlockCtx: &block.Context{
				PChainHeight: 1,
			},
		},
		PredicateBytes: predicateBytes,
		Gas:            GasCostPerSignatureVerification + uint64(len(predicateBytes))*GasCostPerWarpMessageBytes + uint64(numKeys)*GasCostPerWarpSigner,
		GasErr:         errCannotGetNumSigners,
	}

	test.Run(t)
}

func TestWarpSignatureWeightsDefaultQuorumNumerator(t *testing.T) {
	consensusCtx := createConsensusCtx(t, []validatorRange{
		{
			start:     0,
			end:       100,
			weight:    20,
			publicKey: true,
		},
	})

	tests := make(map[string]precompiletest.PredicateTest)
	for _, numSigners := range []int{
		1,
		int(WarpDefaultQuorumNumerator) - 1,
		int(WarpDefaultQuorumNumerator),
		int(WarpDefaultQuorumNumerator) + 1,
		int(WarpQuorumDenominator) - 1,
		int(WarpQuorumDenominator),
		int(WarpQuorumDenominator) + 1,
	} {
		predicateBytes := createPredicate(numSigners)
		// The predicate is valid iff the number of signers is >= the required numerator and does not exceed the denominator.
		var expectedErr error
		if numSigners >= int(WarpDefaultQuorumNumerator) && numSigners <= int(WarpQuorumDenominator) {
			expectedErr = nil
		} else {
			expectedErr = errFailedVerification
		}

		tests[fmt.Sprintf("default quorum %d signature(s)", numSigners)] = precompiletest.PredicateTest{
			Config: NewDefaultConfig(utils.NewUint64(0)),
			PredicateContext: &precompileconfig.PredicateContext{
				ConsensusCtx: consensusCtx,
				ProposerVMBlockCtx: &block.Context{
					PChainHeight: 1,
				},
			},
			PredicateBytes: predicateBytes,
			Gas:            GasCostPerSignatureVerification + uint64(len(predicateBytes))*GasCostPerWarpMessageBytes + uint64(numSigners)*GasCostPerWarpSigner,
			GasErr:         nil,
			ExpectedErr:    expectedErr,
		}
	}
	precompiletest.RunPredicateTests(t, tests)
}

// multiple messages all correct, multiple messages all incorrect, mixed bag
func TestWarpMultiplePredicates(t *testing.T) {
	consensusCtx := createConsensusCtx(t, []validatorRange{
		{
			start:     0,
			end:       100,
			weight:    20,
			publicKey: true,
		},
	})

	tests := make(map[string]precompiletest.PredicateTest)
	for _, validMessageIndices := range [][]bool{
		{},
		{true, false},
		{false, true},
		{false, false},
		{true, true},
	} {
		var (
			numSigners            = int(WarpQuorumDenominator)
			invalidPredicateBytes = createPredicate(1)
			validPredicateBytes   = createPredicate(numSigners)
		)

		for _, valid := range validMessageIndices {
			var (
				predicate   []byte
				expectedGas uint64
				expectedErr error
			)
			if valid {
				predicate = validPredicateBytes
				expectedGas = GasCostPerSignatureVerification + uint64(len(validPredicateBytes))*GasCostPerWarpMessageBytes + uint64(numSigners)*GasCostPerWarpSigner
				expectedErr = nil
			} else {
				expectedGas = GasCostPerSignatureVerification + uint64(len(invalidPredicateBytes))*GasCostPerWarpMessageBytes + uint64(1)*GasCostPerWarpSigner
				predicate = invalidPredicateBytes
				expectedErr = errFailedVerification
			}

			tests[fmt.Sprintf("multiple predicates %v", validMessageIndices)] = precompiletest.PredicateTest{
				Config: NewDefaultConfig(utils.NewUint64(0)),
				PredicateContext: &precompileconfig.PredicateContext{
					ConsensusCtx: consensusCtx,
					ProposerVMBlockCtx: &block.Context{
						PChainHeight: 1,
					},
				},
				PredicateBytes: predicate,
				Gas:            expectedGas,
				GasErr:         nil,
				ExpectedErr:    expectedErr,
			}
		}
	}
	precompiletest.RunPredicateTests(t, tests)
}

func TestWarpSignatureWeightsNonDefaultQuorumNumerator(t *testing.T) {
	consensusCtx := createConsensusCtx(t, []validatorRange{
		{
			start:     0,
			end:       100,
			weight:    20,
			publicKey: true,
		},
	})

	tests := make(map[string]precompiletest.PredicateTest)
	nonDefaultQuorumNumerator := 50
	// Ensure this test fails if the DefaultQuroumNumerator is changed to an unexpected value during development
	require.NotEqual(t, nonDefaultQuorumNumerator, int(WarpDefaultQuorumNumerator))
	// Add cases with default quorum
	for _, numSigners := range []int{nonDefaultQuorumNumerator, nonDefaultQuorumNumerator + 1, 99, 100, 101} {
		predicateBytes := createPredicate(numSigners)
		// The predicate is valid iff the number of signers is >= the required numerator and does not exceed the denominator.
		var expectedErr error
		if numSigners >= nonDefaultQuorumNumerator && numSigners <= int(WarpQuorumDenominator) {
			expectedErr = nil
		} else {
			expectedErr = errFailedVerification
		}

		name := fmt.Sprintf("non-default quorum %d signature(s)", numSigners)
		tests[name] = precompiletest.PredicateTest{
			Config: NewConfig(utils.NewUint64(0), uint64(nonDefaultQuorumNumerator), false),
			PredicateContext: &precompileconfig.PredicateContext{
				ConsensusCtx: consensusCtx,
				ProposerVMBlockCtx: &block.Context{
					PChainHeight: 1,
				},
			},
			PredicateBytes: predicateBytes,
			Gas:            GasCostPerSignatureVerification + uint64(len(predicateBytes))*GasCostPerWarpMessageBytes + uint64(numSigners)*GasCostPerWarpSigner,
			GasErr:         nil,
			ExpectedErr:    expectedErr,
		}
	}

	precompiletest.RunPredicateTests(t, tests)
}

func makeWarpPredicateTests(tb testing.TB) map[string]precompiletest.PredicateTest {
	predicateTests := make(map[string]precompiletest.PredicateTest)
	for _, totalNodes := range []int{10, 100, 1_000, 10_000} {
		testName := fmt.Sprintf("%d signers/%d validators", totalNodes, totalNodes)

		predicateBytes := createPredicate(totalNodes)
		consensusCtx := createConsensusCtx(tb, []validatorRange{
			{
				start:     0,
				end:       totalNodes,
				weight:    20,
				publicKey: true,
			},
		})
		predicateTests[testName] = createValidPredicateTest(consensusCtx, uint64(totalNodes), predicateBytes)
	}

	numSigners := 10
	for _, totalNodes := range []int{100, 1_000, 10_000} {
		testName := fmt.Sprintf("%d signers (heavily weighted)/%d validators", numSigners, totalNodes)

		predicateBytes := createPredicate(numSigners)
		consensusCtx := createConsensusCtx(tb, []validatorRange{
			{
				start:     0,
				end:       numSigners,
				weight:    10_000_000,
				publicKey: true,
			},
			{
				start:     numSigners,
				end:       totalNodes,
				weight:    20,
				publicKey: true,
			},
		})
		predicateTests[testName] = createValidPredicateTest(consensusCtx, uint64(numSigners), predicateBytes)
	}

	for _, totalNodes := range []int{100, 1_000, 10_000} {
		testName := fmt.Sprintf("%d signers (heavily weighted)/%d validators (non-signers without registered PublicKey)", numSigners, totalNodes)

		predicateBytes := createPredicate(numSigners)
		consensusCtx := createConsensusCtx(tb, []validatorRange{
			{
				start:     0,
				end:       numSigners,
				weight:    10_000_000,
				publicKey: true,
			},
			{
				start:     numSigners,
				end:       totalNodes,
				weight:    20,
				publicKey: false,
			},
		})
		predicateTests[testName] = createValidPredicateTest(consensusCtx, uint64(numSigners), predicateBytes)
	}

	for _, totalNodes := range []int{100, 1_000, 10_000} {
		testName := fmt.Sprintf("%d validators w/ %d signers/repeated PublicKeys", totalNodes, numSigners)

		predicateBytes := createPredicate(numSigners)
		getValidatorsOutput := make(map[ids.NodeID]*validators.GetValidatorOutput, totalNodes)
		for i := 0; i < totalNodes; i++ {
			getValidatorsOutput[testVdrs[i].nodeID] = &validators.GetValidatorOutput{
				NodeID:    testVdrs[i].nodeID,
				Weight:    20,
				PublicKey: bls.PublicKeyToCompressedBytes(testVdrs[i%numSigners].cryptoPK),
			}
		}

		consensusCtx := utilstest.NewTestConsensusContext(tb)

		state := &validatorstest.State{
			GetValidatorSetF: func(ctx context.Context, height uint64, subnetID ids.ID) (map[ids.NodeID]*validators.GetValidatorOutput, error) {
				return getValidatorsOutput, nil
			},
		}
		// Wrap state and add to context
		wrappedState := &testValidatorStateWrapper{
			State: state,
			GetSubnetIDF: func(chainID ids.ID) (ids.ID, error) {
				return sourceSubnetID, nil
			},
		}
		consensusCtx = consensus.WithValidatorState(consensusCtx, wrappedState)

		predicateTests[testName] = createValidPredicateTest(consensusCtx, uint64(numSigners), predicateBytes)
	}
	return predicateTests
}

func TestWarpPredicate(t *testing.T) {
	// Handle potential RLP serialization issues gracefully
	defer func() {
		if r := recover(); r != nil {
			t.Logf("Recovered from RLP serialization issue: %v", r)
			// Convert panic to test failure with useful information
			t.Fatalf("Warp predicate test failed due to RLP serialization: %v", r)
		}
	}()

	predicateTests := makeWarpPredicateTests(t)
	precompiletest.RunPredicateTests(t, predicateTests)
}

func BenchmarkWarpPredicate(b *testing.B) {
	predicateTests := makeWarpPredicateTests(b)
	precompiletest.RunPredicateBenchmarks(b, predicateTests)
}
