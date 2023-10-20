import pkg from "zerosync_header_chain_verifier";
const { verify } = pkg;
import fetch from "node-fetch";

async function main() {

    // The public input and proof are extracted from the latest data
    const publicInputUrl = "https://zerosync.org/demo/proofs/latest/air-public-input.json";
  const proofUrl =  "https://zerosync.org/demo/proofs/latest/aggregated_proof.bin";

  const publicInputResponse = await fetch(publicInputUrl);
  const publicInputBytes = new Uint8Array(
    await publicInputResponse.arrayBuffer()
  );
  const proofResponse = await fetch(proofUrl);
  const proofBytes = new Uint8Array(await proofResponse.arrayBuffer());

//  Verifies the proof  and returns the result
  const result = verify(publicInputBytes, proofBytes);
  console.log(result);

}
main();
