%builtins output pedersen range_check bitwise

from starkware.cairo.common.alloc import alloc
from starkware.cairo.common.cairo_builtins import BitwiseBuiltin, HashBuiltin
from starkware.cairo.common.serialize import serialize_word
from starkware.cairo.common.memcpy import memcpy

from crypto.hash_utils import HASH_FELT_SIZE
from utils.python_utils import setup_python_defs
from block_header.block_header import ChainState, validate_and_apply_block_header
from block_header.median import TIMESTAMP_COUNT
from starkware.cairo.cairo_verifier.layouts.all_cairo.cairo_verifier import verify_cairo_proof

from starkware.cairo.stark_verifier.core.stark import StarkProof

from crypto.sha256 import finalize_sha256
from crypto.merkle_mountain_range import mmr_append_leaves, MMR_ROOTS_LEN
from utils.chain_state_utils import (
    validate_block_headers,
    serialize_array,
    serialize_chain_state,
    outputs,
    CHAIN_STATE_SIZE,
    OUTPUT_COUNT,
    PROGRAM_HASH_INDEX,
)

const AGGREGATE_PROGRAM_HASH = 0x92559bd41c8951b211c4cdfcb85540c2fd29ea60d255309658b933d4fbe213;
const BATCH_PROGRAM_HASH = 0x39fa32b361f9ad26278670703cb5ebf55482d6a296b5b1df34617e65c8e7957;

func main{
    output_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr, bitwise_ptr: BitwiseBuiltin*
}() {
    alloc_locals;
    setup_python_defs();

    // initialize sha256_ptr
    let sha256_ptr: felt* = alloc();
    let sha256_ptr_start = sha256_ptr;

    // / 0. Read the aggregate program hash from a hint
    // TODO: implement me
    local INCREMENT_PROGRAM_HASH;
    let prev_proof_mem: StarkProof* = alloc();
    local prev_proof: StarkProof* = prev_proof_mem;
    %{
        ids.INCREMENT_PROGRAM_HASH = program_input["increment_program_hash"]
        segments.write_arg(ids.prev_proof.address_, [(int(x, 16) if x.startswith('0x') else ids.prev_proof.address_ + int(x)) for x in program_input["prev_proof"]])
    %}

    // / 1. Read and verify the previous proof
    let (prev_program_hash, prev_mem_values, prev_output_len) = verify_cairo_proof(prev_proof);
    assert prev_output_len = OUTPUT_COUNT;

    // initialize sha256_ptr
    let sha256_ptr: felt* = alloc();
    let sha256_ptr_start = sha256_ptr;

    // Read the previous state from the program input
    local batch_size: felt;
    %{ ids.batch_size = program_input["batch_size"] %}

    local program_hash: felt;
    let (best_block_hash) = alloc();
    let (prev_timestamps) = alloc();
    let (mmr_roots) = alloc();

    memcpy(best_block_hash, &prev_mem_values[outputs.BEST_BLOCK_HASH], HASH_FELT_SIZE);
    memcpy(prev_timestamps, &prev_mem_values[outputs.TIMESTAMPS], TIMESTAMP_COUNT);
    memcpy(mmr_roots, &prev_mem_values[outputs.MMR_ROOTS], MMR_ROOTS_LEN);

    // [1..8]      best_block_hash
    //      [9]         total_work
    //      [10]        current_target
    //      [11..21]    timestamps
    //      [22]        epoch_start_time
    //      [23..49]    mmr_roots

    // The ChainState of the previous state
    let chain_state = ChainState(
        prev_mem_values[outputs.BLOCK_HEIGHT],
        prev_mem_values[outputs.TOTAL_WORK],
        best_block_hash,
        prev_mem_values[outputs.CURRENT_TARGET],
        prev_mem_values[outputs.EPOCH_START_TIME],
        prev_timestamps,
    );

    // Ensure the program is either the aggregate/batch program or the increment program
    if (prev_program_hash != AGGREGATE_PROGRAM_HASH) {
        if (prev_program_hash != BATCH_PROGRAM_HASH) {
            assert prev_program_hash = INCREMENT_PROGRAM_HASH;
            assert prev_mem_values[PROGRAM_HASH_INDEX] = INCREMENT_PROGRAM_HASH;
        }
    }

    // Output the previous state
    serialize_chain_state(chain_state);
    serialize_array(prev_mem_values + outputs.MMR_ROOTS, MMR_ROOTS_LEN);

    // Validate all blocks in this batch and update the state
    let (block_hashes) = alloc();
    with sha256_ptr, chain_state {
        validate_block_headers(batch_size, block_hashes);
    }
    finalize_sha256(sha256_ptr_start, sha256_ptr);
    mmr_append_leaves{hash_ptr=pedersen_ptr, mmr_roots=mmr_roots}(block_hashes, batch_size);

    // Output the next state
    serialize_chain_state(chain_state);
    serialize_array(mmr_roots, MMR_ROOTS_LEN);
    // Padding zero such that NUM_OUTPUTS of the increment program and batch program are equal
    serialize_word(INCREMENT_PROGRAM_HASH);

    return ();
}
