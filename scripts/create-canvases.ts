#!/usr/bin/env ts-node

import { SuiClient } from "@mysten/sui/client";
import { Transaction } from "@mysten/sui/transactions";

import { Ed25519Keypair } from "@mysten/sui/keypairs/ed25519";

const PACKAGE_ID =
  "0x2a54286c2f25d35e7254db31ce76fe567d8fd03aad2445e23551fbb1820dbc23";
const META_CANVAS_ID =
  "0x396d5e541ccb36a2315cf580bd918442941fad93d4fcd967811dd9376527328d";
const META_CANVAS_CAP =
  "0x4d934b1de0afc2c8230271f70c7fae65be0ef2d1b37fb867ac2d5e04f50705dd";
const PRIVATE_KEY_BASE64 =
  "suiprivkey1qr0c220rnccmj0hn3l3clren2lp9zdvx04qkvudvav9zsuxxt0lqgrvdadz";
const RPC_URL = "https://sui-testnet-rpc.publicnode.com:443";

import * as readline from "readline";

const rl = readline.createInterface({
  input: process.stdin,
  output: process.stdout,
});

function waitForInput(query: string): Promise<string> {
  return new Promise((resolve) => {
    rl.question(query, (answer) => {
      resolve(answer);
    });
  });
}
/**
 * Figure out how many canvases remain to fill the "next ring".
 * If we have fully completed ring `r`, we move to `r+1`.
 * Otherwise, we finish the current ring `r`.
 */
function numCanvasesToNextRing(length: number): number {
  const r = Math.floor(Math.sqrt(length));
  const offset = length - r * r;
  const ringSize = 2 * r + 1;

  // If offset == ringSize, that means ring r is complete,
  // and we actually move to ring (r+1).
  if (offset === ringSize) {
    const rNext = r + 1;
    return 2 * rNext + 1;
  } else {
    // Otherwise, just finish out ring r:
    return ringSize - offset;
  }
}

async function main() {
  // create a client connected to devnet
  const client = new SuiClient({ url: RPC_URL });

  // Create a keypair:
  const keypair = Ed25519Keypair.fromSecretKey(PRIVATE_KEY_BASE64);
  const address = keypair.getPublicKey().toSuiAddress();

  let res = (await client.call("sui_getObject", [
    META_CANVAS_ID,
    {
      showContent: true,
    },
  ])) as any;

  let length = Number(res?.data.content.fields.canvases.fields.size);

  // 4. Figure out how many canvases we need to add to complete the next ring:
  let toAdd = numCanvasesToNextRing(length);

  await waitForInput(
    `Need to add ${toAdd} new canvases. Press enter to continue...`
  );

  while (toAdd > 0) {
    let txs = 0;
    let tx = new Transaction();
    while (txs < 7 && toAdd > 0) {
      tx.moveCall({
        target: `${PACKAGE_ID}::meta_canvas::add_new_canvas`,
        arguments: [tx.object(META_CANVAS_ID), tx.object(META_CANVAS_CAP)],
      });
      txs += 1;
      toAdd -= 1;
    }

    const txResult = await client.devInspectTransactionBlock({
      sender: address,
      transactionBlock: tx,
    });

    let gasUsed = txResult.effects.gasUsed;

    let total_gas_fees =
      Number(gasUsed.computationCost) + Number(gasUsed.storageCost);

    let balance = await client.getBalance({
      owner: address,
    });

    if (Number(balance.totalBalance) < total_gas_fees) {
      await waitForInput(
        `Insufficient funds. Need ${total_gas_fees} but only have ${balance}. Send Sui to ${address}. Press enter to continue...`
      );
      return;
    }

    await waitForInput(
      `About to add ${txs} new canvases. Press enter to continue...`
    );

    await client.signAndExecuteTransaction({
      signer: keypair,
      transaction: tx,
    });
  }

  console.log("All new canvases added successfully!");
}

// Run the script
main().catch((e) => {
  console.error("Script failed:", e);
  process.exit(1);
});
