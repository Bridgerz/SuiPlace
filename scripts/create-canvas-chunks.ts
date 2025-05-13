#!/usr/bin/env ts-node

import * as dotenv from "dotenv";
dotenv.config();
import { SuiClient } from "@mysten/sui/client";
import { Transaction } from "@mysten/sui/transactions";

import { Ed25519Keypair } from "@mysten/sui/keypairs/ed25519";

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
function numChunksToNextRing(length: number): number {
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
  const RPC_URL = process.env.RPC_URL!;
  const PRIVATE_KEY_BASE64 = process.env.PRIVATE_KEY_BASE64!;
  const PACKAGE_ID = process.env.PACKAGE_ID!;
  const CANVAS_ID = process.env.CANVAS_ID!;
  const CANVAS_ADMIN_CAP = process.env.CANVAS_ADMIN_CAP!;

  // create a client connected to devnet
  const client = new SuiClient({ url: RPC_URL });

  // Create a keypair:
  const keypair = Ed25519Keypair.fromSecretKey(PRIVATE_KEY_BASE64);
  const address = keypair.getPublicKey().toSuiAddress();

  let res = (await client.call("sui_getObject", [
    CANVAS_ID,
    {
      showContent: true,
    },
  ])) as any;

  let length = Number(res?.data.content.fields.chunks.fields.size);

  // 4. Figure out how many chunks we need to add to complete the next ring:
  let toAdd = numChunksToNextRing(length);

  await waitForInput(
    `Need to add ${toAdd} new chunks. Press enter to continue...`
  );

  while (toAdd > 0) {
    let txs = 0;
    let tx = new Transaction();
    while (txs < 7 && toAdd > 0) {
      tx.moveCall({
        target: `${PACKAGE_ID}::canvas::add_new_chunk`,
        arguments: [tx.object(CANVAS_ID), tx.object(CANVAS_ADMIN_CAP)],
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
    }

    await waitForInput(
      `About to add ${txs} new chunks. Press enter to continue...`
    );

    await client.signAndExecuteTransaction({
      signer: keypair,
      transaction: tx,
    });
  }

  console.log("All new chunks added successfully!");

  process.exit(0);
}

// Run the script
main().catch((e) => {
  console.error("Script failed:", e);
  process.exit(1);
});
