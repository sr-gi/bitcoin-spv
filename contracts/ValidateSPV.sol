pragma solidity 0.4.25;

/** @title ValidateSPV*/
/** @author Summa (https://summa.one) */

import {BytesLib} from "./BytesLib.sol";
import {SafeMath} from "./SafeMath.sol";
import {BTCUtils} from "./BTCUtils.sol";


library ValidateSPV {

    using BTCUtils for bytes;
    using BytesLib for bytes;
    using SafeMath for uint256;

    enum OutputTypes { NONE, WPKH, WSH, OP_RETURN }
    // /// @notice         Parses, a tx, valides its inclusdion in the block, stores to the
    // /// @notice         mapping
    // /// @param _tx      The raw byte tx
    // /// @param _proof   The raw byte proof (concatenated LE hashes)
    // /// @param _header  The raw byte header
    // /// @return         true if fully valid, false otherwise
    // function validate(bytes _tx, bytes _proof, uint _index, bytes _header) public returns (bytes32);

    /// @notice         Validates a tx from a bytestring
    /// @dev            This supports ONLY WITNESS INPUTS AND OUTPUTS
    /// @param _tx      Raw bytes tx
    /// @return         Transaction id, little endian
    /// arrry of uints that are output types, nInputs, numOuptuts, locktime, txid, inputIndices, outputIndices
    /// add getter functions that tkes _tx and index and returns iths input/output
    function validateTransaction(
        bytes _tx
    ) public pure returns (
        uint8 _nInputs,
        uint8 _nOutputs,
        bytes _prefix,
        bytes _inputs,
        bytes _outputs,
        bytes _locktime,
        bytes32 _txid
    ) {

        _prefix = _tx.extractPrefix();

        // If invalid prefix, bubble up error
        if (!validatePrefix(_prefix)) { return; }

        (_nInputs, _inputs) = extractAllInputs(_tx);

        (_nOutputs, _outputs) = extractAllOutputs(_tx);

        _locktime = _tx.extractLocktimeLE();

        _txid = transactionHash(_prefix, _inputs, _outputs, _locktime);
    }

    function extractAllInputs(bytes _tx) public pure returns (uint8 _nInputs, bytes _inputs) {
        _nInputs = _tx.extractNumInputs();

        for (uint8 i = 0; i < _nInputs; i++) {
            _inputs = _inputs.concat(_tx.extractInputAtIndex(i));
        }
    }

    function extractAllOutputs(bytes _tx) public pure returns (uint8 _nOutputs, bytes _outputs) {
        _nOutputs = _tx.extractNumOutputs();

        for (uint8 i = 0; i < _nOutputs; i++) {
            _outputs = _outputs.concat(_tx.extractOutputAtIndex(i));
        }
    }

    function transactionHash(
        bytes _prefix,
        bytes _inputs,
        bytes _outputs,
        bytes _locktime
    ) public pure returns (bytes32) {
        // Get transaction hash dSha256(version + inputs + outputs + locktime)
        return abi.encodePacked(_prefix, _inputs, _outputs, _locktime).hash256();
    }

    /// @notice         Validates the first 6 bytes of a block
    /// @dev            First byte is the version. The next must be 0x0000000001
    /// @param _bytes   Raw byte string whos first 6 bytes are the prefix
    /// @return         true if valid, otherwise false
    function validatePrefix(bytes _bytes) public pure returns (bool) {

        if (_bytes.length < 6) { return false; }

        bytes32 _versionHash = keccak256(_bytes.slice(0, 1));

        // Return true if prefix is version 1 or 2 and has segwit flag
        return ((_versionHash == keccak256(hex'01') || _versionHash == keccak256(hex'02'))
                && keccak256(_bytes.slice(1, 5)) == keccak256(hex'0000000001'));
    }

    function getInput(bytes _tx, uint8 _index) public pure returns (uint32 _sequence, bytes _outpoint) {
        (_sequence, _outpoint) = parseInput(_tx.extractInputAtIndex(_index)); 
    }

    function getOutput(bytes _tx, uint8 _index) public pure returns (
        uint256 _value,
        uint8 _outputType,
        bytes _payload
    ) {
        (_value, _outputType, _payload) = parseOutput(_tx.extractOutputAtIndex(_index)); 
    }

    /// @notice         Parses a tx input from raw input bytes
    /// @dev            Checks for blank scriptSig
    /// @param _input   Raw bytes tx input
    /// @return         Tx input sequence number and outpoint
    function parseInput(bytes _input) public pure returns (uint32 _sequence, bytes _outpoint) {

        // Require segwit: if no 00 scriptSig, error
        require(keccak256(_input.slice(36, 1)) == keccak256(hex'00'), "No 00 scriptSig found.");

        // Require that input is 41 bytes
        require(_input.length == 41, "Tx input must be 41 bytes.");

        return (_input.extractSequence(), _input.extractOutpoint());
    }

    /// @notice         Parses a tx output from raw output bytes
    /// @dev            Differentiates by output script prefix
    /// @param _output  Raw bytes tx output
    /// @return         Tx output value, output type, payload
    function parseOutput(bytes _output) public pure returns (uint64 _value, uint8 _outputType, bytes _payload) {

        _value = _output.extractValue();

        if (keccak256(_output.slice(9, 1)) == keccak256(hex'6a')) {
            // OP_RETURN
            _outputType = uint8(OutputTypes.OP_RETURN);
            _payload = _output.extractOpReturnData();
        } else {
            bytes32 _prefixHash = keccak256(_output.slice(8, 2));
            if (_prefixHash == keccak256(hex'2200')) {
                // P2WSH
                _outputType = uint8(OutputTypes.WSH);
                _payload = _output.slice(11, 32);
            } else if (_prefixHash == keccak256(hex'1600')) {
                // P2WPKH
                _outputType = uint8(OutputTypes.WPKH);
                _payload = _output.slice(11, 20);
            } else {
                // If unidentifiable output type, error
                require(false, "Tx output must be a WPKH, WSH, or OP_RETURN.");
            } 
        }

        return (_value, _outputType, _payload);
    }

    /// @notice         Parses a block header struct from a bytestring
    /// @dev            Block headers are always 80 bytes, see Bitcoin docs
    /// @param _header  Raw bytes header
    /// @return         Header digest, version, previous block header hash, merkle root, timestamp, target, nonce
    function parseHeader(bytes _header) public pure returns (
        bytes32 _digest,
        uint32 _version,
        bytes32 _prevHash,
        bytes32 _merkleRoot,
        uint32 _timestamp,
        uint256 _target,
        uint32 _nonce
    ) {
        // If header has an invalid length, bubble up error
        // Check header chain length
        require(validateHeaderLength(_header), "Header chain must be divisible by 80.");

        _digest = abi.encodePacked(_header.hash256()).reverseEndianness().toBytes32();
        _version = uint32(_header.slice(0, 4).reverseEndianness().bytesToUint());
        _prevHash = _header.extractPrevBlockLE().toBytes32();
        _merkleRoot = _header.extractMerkleRootLE().toBytes32();
        _timestamp = _header.extractTimestamp();
        _target = _header.extractTarget();
        _nonce = uint32(_header.slice(76, 4).reverseEndianness().bytesToUint());

        return(_digest, _version, _prevHash, _merkleRoot, _timestamp, _target, _nonce);
    }

    /// @notice             Checks validity of header chain
    /// @notice             Compares the hash of each header to the prevHash in the next header
    /// @param _headers     Raw byte array of header chain
    /// @return             true if header chain is valid, false otherwise
    function validateHeaderChain(bytes _headers) public pure returns (bool) {

<<<<<<< HEAD
    struct Transaction {
        bytes32 txid;               // 32 byte tx id, little endian
        uint32 locktime;            // 4 byte locktime
        uint8 numInputs;            // number tx inputs
        uint8 numOutputs;           // number tx outputs
        mapping (uint8 => TxIn) inputs;
        mapping (uint8 => TxOut) outputs;
        /*TxIn[] inputs;              // tx input struct array
        TxOut[] outputs;            // tx output struct array*/
    }
=======
        // Check header chain length
        require(validateHeaderLength(_headers), "Header chain must be divisible by 80.");

        uint _nHeaders = _headers.length / 80;

        // Initialize header start index
        uint256 _start = 0;
        bytes memory _prevHeader;
        bytes memory _header;

        for (uint i = 0; i < _nHeaders - 1; i++) {

            // Previous header
            _prevHeader = _headers.slice(_start, 80);

            // Previous header hash
            bytes32 _prevHeaderDigest = _prevHeader.hash256();

            // Increment start index by 80 for next header
            _start = _start.add(80);
>>>>>>> ValidateSPV from contract to library, split up Header functions

            // Current header
            _header = _headers.slice(_start, 80);

            // Check if the hash of the previous header and the current header prevHash are equal
            require(
                validateHeaderPrevHash(_header, _prevHeaderDigest),
                "Header chain prevHash must match previous header digest.");
        }

        return true;
    }

    function validateHeaderWork(bytes32 _digest, uint256 _target) public pure returns (bool) {
        require(_digest != bytes32(0));
        return (abi.encodePacked(_digest).bytesToUint() < _target);
    }

    function validateHeaderPrevHash(bytes _header, bytes32 _prevHeaderDigest) public pure returns (bool) {

        // prevHash of _header
        bytes32 _prevHash = _header.extractPrevBlockLE().toBytes32();

        if (_prevHash != _prevHeaderDigest) { return false; }

        return true;
    }

    /// @notice             Validates that headers are the correct length
    /// @dev                Each header is 80 bytes
    /// @param _headers     Raw byte array of header chain
    /// @return             true if header byte array is divisible by 80, false otherwise
    function validateHeaderLength(bytes _headers) public pure returns (bool) {
        return (_headers.length % 80 == 0);
    }
}