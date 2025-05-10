#!/usr/bin/env ts-node

import * as dotenv from "dotenv";
dotenv.config();
import { SuiClient } from "@mysten/sui/client";
import { Transaction } from "@mysten/sui/transactions";

import { Ed25519Keypair } from "@mysten/sui/keypairs/ed25519";

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

  let tx = new Transaction();

  for (let i = 0; i < 100; i++) {
    tx.moveCall({
      target: `${PACKAGE_ID}::canvas::add_new_chunk`,
      arguments: [tx.object(CANVAS_ID), tx.object(CANVAS_ADMIN_CAP)],
    });
  }

  await client.signAndExecuteTransaction({
    signer: keypair,
    transaction: tx,
  });

  console.log("All new chunks added successfully!");

  process.exit(0);
}

// Run the script
main().catch((e) => {
  console.error("Script failed:", e);
  process.exit(1);
});
