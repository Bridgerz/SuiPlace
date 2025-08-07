#!/usr/bin/env ts-node
import * as dotenv from "dotenv";
dotenv.config();

import { SuiClient } from "@mysten/sui/client";
import { isValidSuiAddress } from "@mysten/sui/utils";
import { Transaction, coinWithBalance } from "@mysten/sui/transactions";
import { Ed25519Keypair } from "@mysten/sui/keypairs/ed25519";
import * as readline from "readline";
import airdropData from "./airdrop.json";

// ----------------- helpers -----------------
const rl = readline.createInterface({ input: process.stdin, output: process.stdout });
const ask = (q: string) => new Promise<string>((r) => rl.question(q, r));
const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));

// ----------------- main -----------------
async function main() {
  const RPC_URL = process.env.RPC_URL!;
  const PRIVATE_KEY_BASE64 = process.env.PRIVATE_KEY_BASE64!;
  const AIRDROP_PACKAGE_ID = process.env.AIRDROP_PACKAGE_ID!;
  const COIN_TYPE_ARGUMENT = process.env.COIN_TYPE_ARGUMENT!;
  const AIRDROP_OBJECT_ID = process.env.AIRDROP_OBJECT_ID!;
  const AIRDROP_ADMIN_CAP = process.env.AIRDROP_ADMIN_CAP!;

  const client = new SuiClient({ url: RPC_URL });
  const keypair = Ed25519Keypair.fromSecretKey(PRIVATE_KEY_BASE64);
  const signerAddress = keypair.getPublicKey().toSuiAddress();
  console.log("Using signer:", signerAddress);

  await ask("Creating AirDrop object… [enter]");
  // --- 1. create the airdrop object once ------------------------------------

  await ask(`About to add ${airdropData.length} claims **one-by-one**… [enter]`);

  // --- 2. add each claim in its own tx -------------------------------------
  let remaining = airdropData.length;
  for (const { address, amount } of airdropData) {
    if (!isValidSuiAddress(address)) throw new Error(`Invalid Sui address: ${address}`);

    const tx = new Transaction();
    tx.setSender(signerAddress);

    const suiAmount = amount * 100000000; 

    tx.moveCall({
      target: `${AIRDROP_PACKAGE_ID}::airdrop::add_claims`,
      arguments: [
        tx.object(AIRDROP_OBJECT_ID),
        tx.object(AIRDROP_ADMIN_CAP),
        tx.pure.vector("address", [address]),
        tx.pure.vector("u64", [suiAmount]),
        coinWithBalance({
          balance: suiAmount,
          type: COIN_TYPE_ARGUMENT,
          useGasCoin: true,
        }),
      ],
      typeArguments: [COIN_TYPE_ARGUMENT],
    });

    tx.setGasBudget(2_000_000_000); // 2 SUI – tune for your needs

    // Optional dev-inspect to estimate fees
    const preview = await client.devInspectTransactionBlock({
      sender: signerAddress,
      transactionBlock: tx,
    });
    const estGas =
      Number(preview.effects.gasUsed.computationCost) +
      Number(preview.effects.gasUsed.storageCost);
    const balance = await client.getBalance({ owner: signerAddress });
    if (Number(balance.totalBalance) < estGas)
      await ask(
        `Need ~${estGas} MIST but balance is ${balance.totalBalance}. Top-up and press enter…`,
      );

    // Execute for real
    try {
      await client.signAndExecuteTransaction({ signer: keypair, transaction: tx });
      remaining--;
      process.stdout.write(`✅ added claim for ${address} | remaining: ${remaining}   \r`);
    } catch (err) {
      console.error(`❌ tx failed for ${address}:`, err);
      await ask("Press enter to retry…");
      continue; // go back and retry same claim (array not modified)
    }

    // be kind to RPC
    await sleep(500);
  }

  console.log(`\nAll claims added! Airdrop ready at ${AIRDROP_OBJECT_ID}`);
  process.exit(0);
}

main().catch((e) => {
  console.error("Script failed:", e);
  process.exit(1);
});
