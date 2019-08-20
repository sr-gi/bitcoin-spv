package btcspv

import (
	"bytes"
	"errors"

	sdk "github.com/cosmos/cosmos-sdk/types"
)

// import (
// 	"bytes"
// 	// "crypto/sha256"
// 	// "encoding/binary"
// 	// "encoding/hex"
// 	// "errors"
// 	// "math/big"
// 	// sdk "github.com/cosmos/cosmos-sdk/types"
// 	// "golang.org/x/crypto/ripemd160"
// )

type INPUT_TYPE int

const (
	INPUT_NONE    INPUT_TYPE = 0
	LEGACY        INPUT_TYPE = 1
	COMPATIBILITY INPUT_TYPE = 2
	WITNESS       INPUT_TYPE = 3
)

type OUTPUT_TYPE int

const (
	OUTPUT_NONE OUTPUT_TYPE = 0
	WPKH        OUTPUT_TYPE = 1
	WSH         OUTPUT_TYPE = 2
	OP_RETURN   OUTPUT_TYPE = 3
	PKH         OUTPUT_TYPE = 4
	SH          OUTPUT_TYPE = 5
	NONSTANDARD OUTPUT_TYPE = 6
)

func prove(txid []byte, merkleRoot []byte, intermediateNodes []byte, index uint) bool {
	// Shortcut the empty-block case
	if bytes.Equal(txid, merkleRoot) && index == 0 && len(intermediateNodes) == 0 {
		return true
	}

	proof := []byte{}
	proof = append(proof, txid...)
	proof = append(proof, intermediateNodes...)
	proof = append(proof, merkleRoot...)

	return VerifyHash256Merkle(proof, index)
}

func CalculateTxId(version, vin, vout, locktime []byte) []byte {
	txid := []byte{}
	txid = append(txid, version...)
	txid = append(txid, vin...)
	txid = append(txid, vout...)
	txid = append(txid, locktime...)
	return Hash256(txid)
}

func ParseInput(input []byte) (uint, []byte, uint, INPUT_TYPE) {
	// NB: If the scriptsig is exactly 00, we are WITNESS.
	// Otherwise we are Compatibility or LEGACY
	var sequence uint
	var witnessTag []byte
	var inputType INPUT_TYPE

	if input[36] != 0 {
		sequence = ExtractSequenceLegacy(input)
		witnessTag = input[36:39]

		if bytes.Equal(witnessTag, []byte{34, 0, 32}) || bytes.Equal(witnessTag, []byte{32, 0, 20}) {
			inputType = COMPATIBILITY
		} else {
			inputType = LEGACY
		}
	} else {
		sequence = ExtractSequenceWitness(input)
		inputType = WITNESS
	}

	inputId := ExtractInputTxId(input)
	inputIndex := ExtractTxIndex(input)

	return sequence, inputId, inputIndex, inputType
}

func ParseOutput(output []byte) (uint, OUTPUT_TYPE, []byte) {
	value := ExtractValue(output)
	var outputType OUTPUT_TYPE
	var payload []byte

	if output[9] == 0x6a {
		outputType = OP_RETURN
		payload, _ = ExtractOpReturnData(output)
	} else {
		prefixHash := output[8:10]
		if bytes.Equal(prefixHash, []byte{34, 0}) {
			outputType = WSH
			payload = output[11:43]
		} else if bytes.Equal(prefixHash, []byte{22, 0}) {
			outputType = WPKH
			payload = output[11:31]
		} else if bytes.Equal(prefixHash, []byte{25, 118}) {
			outputType = PKH
			payload = output[12:32]
		} else if bytes.Equal(prefixHash, []byte{23, 169}) {
			outputType = SH
			payload = output[11:31]
		} else {
			outputType = NONSTANDARD
			payload = []byte{}
		}
	}

	return value, outputType, payload
}

func ParseHeader(header []byte) ([]byte, uint, []byte, []byte, uint, sdk.Int, uint, error) {
	if len(header) != 80 {
		return nil, 0, nil, nil, 0, sdk.NewInt(0), 0, errors.New("Malformatted header. Must be exactly 80 bytes.")
	}

	digest := ReverseEndianness(Hash256(header))
	version := bytesToUint(ReverseEndianness(header[0:4]))
	prevHash := ExtractPrevBlockHashLE(header)
	merkleRoot := ExtractMerkleRootLE(header)
	timestamp := ExtractTimestamp(header)
	target := ExtractTarget(header)
	nonce := bytesToUint(ReverseEndianness(header[76:80]))

	return digest, version, prevHash, merkleRoot, timestamp, target, nonce, nil
}

func ValidateHeaderChain(headers []byte) (uint, error) {
	// // Check header chain length

	if len(headers)%80 != 0 {
			return 0, errors.New("Header bytes not multiple of 80.")
	}

	var digest []byte
	totalDifficulty := sdk.NewInt(0)

	for i := 0; i < len(headers); i++ {
			start := i * 80
			header := headers[start : start+80]

			// After the first header, check that headers are in a chain
			// if i != 0 {
			// 		if !ValidateHeaderPrevHash(header, digest) {
			// 				return 0, errors.New("Header bytes not a valid chain.")
			// 		}
			// }

			// ith header target
			target := ExtractTarget(header)

			// // Require that the header has sufficient work
			// digest = Hash256(header)
			// if !ValidateHeaderWork(ReverseEndianness(digest), target) {
			// 		return 0, errors.New("Header does not meet its own difficulty target.")
			// }

			totalDifficulty += CalculateDifficulty(target)
	}
	return totalDifficulty, nil
}

// func ValidateHeaderPrevHash() {

// }

// func ValidateHeaderChain() {

// }
