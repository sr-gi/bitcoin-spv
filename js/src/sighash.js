/* global BigInt */

import * as utils from './utils';
import * as BTCUtils from './BTCUtils';

const NULL_HASH = new Uint8Array(32);
const U32_MAX = new Uint8Array([0xff, 0xff, 0xff, 0xff]);

/**
 * @typedef {Object} Sighash
 * @property {Uint8Array}   digest The sighash digest
 * @property {number}       sighashFlag The sighash flag
 * @property {boolean}      possibleAbsoluteLock If nSequence locks might be active
 * @property {boolean}      possibleRelativeLock If nLocktime might be active
 * @property {boolean}      updateableOutputs
 * @property {boolean}      updateableInputs
 */

/**
 * @typedef {Object} Tx
 * @property {Uint8Array}   version 4-byte version
 * @property {Uint8Array}   vin The vin
 * @property {Uint8Array}   vout The vout
 * @property {Uint8Array}   locktime 4-byte locktime
 */

/**
 * @typedef {Object} SerTx
 * @property {string}     version 4-byte version
 * @property {string}     vin The vin
 * @property {string}     vout The vout
 * @property {string}     locktime 4-byte locktime
 */

/**
 * 
 * Validates a flag
 * 
 * @param {number}      flag The first byte of a VarInt
 * @returns {boolean}   True if the flag is valid
 */
export function validateFlag(flag) {
  if (flag !== 0x01 && flag !== 0x03 && flag !== 0x81 && flag !== 0x83) return false;
  return true;
}

/**
 *
 * Parses a vin into an array of inputs
 *
 * @param {Uint8Array}    vin The vin
 * @returns {array}       An array of inputs (type Uint8Array)
 */
export function parseVin(vin) {
  const { nIns } = BTCUtils.parseVarInt(vin);
  const inputs = [];
  for (let i = 0; i < nIns; i += 1) {
    inputs.push(BTCUtils.extractInputAtIndex(i));
  }
  return inputs;
}

// returns an array of uint8arrays.
/**
 *
 * Parses a vout into an array of outputs
 *
 * @param {Uint8Array}    vout The vout
 * @returns {array}       An array of outputs (type Uint8Array)
 */
export function parseVout(vout) {
  const { nOuts } = BTCUtils.parseVarInt(vout);
  const outputs = [];
  for (let i = 0; i < nOuts; i += 1) {
    outputs.push(BTCUtils.extractOutputAtIndex(i));
  }
  return outputs;
}

/**
 *
 * Hashes prevouts according to BIP143 semantics.
 * 
 * For BIP143 (Witness and Compatibility sighash) documentation, see here:
 * - https://github.com/bitcoin/bips/blob/master/bip-0143.mediawiki
 *
 * @param {array}         inputs An array of inputs (type Uint8Array)
 * @param {number}        flag The first byte of a VarInt
 * @returns {Uint8Array}  The hash of the Prevouts
 */
export function hashPrevouts(inputs, flag) {
  if ((flag & 0x80) === 0x80) {
    return NULL_HASH;
  }

  const preimage = utils.concatUint8Arrays(
    inputs.map(BTCUtils.extractOutpoint)
  );
  return utils.hash256(preimage);
}

/**
 *
 * Hashes sequence according to BIP143 semantics.
 * 
 * For BIP143 (Witness and Compatibility sighash) documentation, see here:
 * - https://github.com/bitcoin/bips/blob/master/bip-0143.mediawiki
 *
 * @param {array}         inputs An array of inputs (type Uint8Array)
 * @param {number}        flag The first byte of a VarInt
 * @returns {Uint8Array}  The hash of the Sequence
 */
export function hashSequence(inputs, flag) {
  if ((flag & 0x80) === 0x80 || (flag & 0x03) === 0x03) {
    return NULL_HASH;
  }
  const preimage = utils.concatUint8Arrays(
    inputs.map(BTCUtils.extractSequenceLELegacy)
  );
  return utils.hash256(preimage);
}

/**
 *
 * Hashes outputs according to BIP143 semantics.
 * 
 * For BIP143 (Witness and Compatibility sighash) documentation, see here:
 * - https://github.com/bitcoin/bips/blob/master/bip-0143.mediawiki
 *
 * @param {array}         outputs An array of outputs (type Uint8Array)
 * @returns {Uint8Array}  The hash of the Outputs
 */
export function hashOutputs(outputs) {
  if (outputs.length === 0) {
    return NULL_HASH;
  }
  return utils.hash256(utils.concatUint8Arrays(...outputs));
}

/**
 *
 * Checks if nSequence locks might be active
 *
 * @param {array}         inputs An array of inputs (type Uint8Array)
 * @param {Uint8Array}    locktime 4-byte tx locktime
 * @param {number}        flag The first byte of a VarInt
 * @returns {boolean}     True if there is a lock
 */
export function possibleAbsoluteLock(inputs, locktime, flag) {
  if ((flag && 0x80) === 0x80) return true;

  const sequences = inputs.map(BTCUtils.extractSequenceLegacy);
  if (sequences.filter(s => !utils.typedArraysAreEqual(s, U32_MAX)).length === 0) return false;

  const lock = utils.bytesToUint(locktime);
  if (lock > BigInt(1550000000) || (lock > BigInt(600000) && lock < BigInt(500000000))) {
    return false;
  }
  return true;
}

/**
 *
 * Checks if nLocktime might be active
 *
 * @param {array}         inputs An array of inputs (type Uint8Array)
 * @param {Uint8Array}    version 4-byte version
 * @returns {boolean}     True if there is a lock
 */
export function possibleRelativeLock(inputs, version) {
  if (version[0] === 1) return false;

  const sequences = inputs.map(BTCUtils.extractSequenceLegacy);
  for (let i = 0; i < sequences.length; i += 1) {
    if (!(sequences[i][3] & 0x80) === 0x80) return true;
  }

  return false;
}

// TODO: make typedef for tx
/**
 *
 * Calculates sighash
 * 
 * @dev All args are deserialized
 *
 * @param {tx}            tx The tx
 * @param {number}        index The index
 * @param {number}        sighashFlag The first byte of a VarInt
 * @param {}              prevoutScript
 * @param {}              prevoutValue
 * @returns {Sighash}     Data regarding the sighash
 */
export function sighash(tx, index, sighashFlag, prevoutScript, prevoutValue) {
  if (!BTCUtils.validateVin(tx.vin)) {
    throw Error('Malformatted vin');
  }
  if (!BTCUtils.validateVout(tx.vout)) {
    throw Error('Malformatted vout');
  }

  let inputs = parseVin(tx.vin);
  let outputs = parseVout(tx.vout);

  if ((sighashFlag & 0x80) === 0x80) {
    inputs = [inputs[index]]; // If ACP, just 1 input
  }
  if ((sighashFlag & 0x03) === 0x03) {
    outputs = [outputs[index]]; // If SINGLE, just 1 output
  }

  const preimage = utils.concatUint8Arrays(
    tx.version,
    hashPrevouts(inputs, sighashFlag),
    hashSequence(inputs, sighashFlag),
    BTCUtils.extractOutpoint(inputs[index]),
    prevoutScript,
    prevoutValue,
    BTCUtils.extractSequenceLegacy(inputs[index]),
    hashOutputs(outputs),
    tx.locktime,
    new Uint8Array([sighashFlag, 0, 0, 0]), // sighashFlag as LE u32
  );

  return {
    digest: utils.hash256(preimage),
    sighashFlag,
    possibleAbsoluteLock: possibleAbsoluteLock(inputs, tx.locktime, sighashFlag),
    possibleRelativeLock: possibleRelativeLock(inputs, tx.version),
    updateableOutputs: (sighashFlag & 0x03) === 0x03,
    updateableInputs: (sighashFlag & 0x80) === 0x80,
  };
}

/**
 *
 * Deserializes the args for `sighash` from hex
 *
 * @param {SerTx}         serTx The tx all as hex
 * @param {}              serPrevoutScript
 * @param {}              serPrevoutValue
 * @returns {object}      The tx object (deserialized version, vin, vout and locktime),
 *                        prevoutScript and prevoutValue
 */
export function deserSighashArgs(serTx, serPrevoutScript, serPrevoutValue) {
  const tx = {};
  const txKeys = ['version', 'vin', 'vout', 'locktime'];
  txKeys.forEach((k) => {
    tx[k] = utils.deserializeHex(serTx[k]);
  });

  const prevoutScript = utils.deserializeHex(serPrevoutScript);
  const prevoutValue = utils.deserializeHex(serPrevoutValue);
  return { tx, prevoutScript, prevoutValue };
}

/**
 *
 * Runs `deserSighashArgs` and then`sighash`
 *
 * @param {SerTx}         serTx The tx all as hex
 * @param {}              index
 * @param {number}        sighashFlag The first byte of a VarInt
 * @param {}              prevoutScript
 * @param {}              prevoutValue
 * @returns {Sighash}     Data regarding the sighash
 */
export function deserAndSighash(serTx, index, sighashFlag, prevoutScript, prevoutValue) {
  const deser = deserSighashArgs(serTx, prevoutScript, prevoutValue);
  return sighash(deser.tx, index, sighashFlag, deser.prevoutScript, deser.prevoutValue);
}