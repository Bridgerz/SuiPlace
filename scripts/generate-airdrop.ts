#!/usr/bin/env ts-node

import * as dotenv from "dotenv";
dotenv.config();
import { SuiClient, SuiObjectChange } from "@mysten/sui/client";
 import { isValidSuiAddress } from '@mysten/sui/utils';
import { Transaction, coinWithBalance } from "@mysten/sui/transactions";

import { Ed25519Keypair } from "@mysten/sui/keypairs/ed25519";

import * as readline from "readline";

import airdropData  from "./airdrop.json";

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

async function main() {
  const RPC_URL = process.env.RPC_URL!;
  const PRIVATE_KEY_BASE64 = process.env.PRIVATE_KEY_BASE64!;
  const AIRDROP_PACKAGE_ID = process.env.AIRDROP_PACKAGE_ID!;
  const COIN_TYPE_ARGUMENT = process.env.COIN_TYPE_ARGUMENT!;

  // create a client connected to devnet
  const client = new SuiClient({ url: RPC_URL });

  // Create a keypair:
  const keypair = Ed25519Keypair.fromSecretKey(PRIVATE_KEY_BASE64);
  const signer_address = keypair.getPublicKey().toSuiAddress();

  console.log("Using signer address: ", signer_address);

  await waitForInput(
    `Creating AirDrop Object. Press enter to continue...`
  );

  // Create the airdrop object
  const tx = new Transaction();
  let cap = tx.moveCall({
    target: `${AIRDROP_PACKAGE_ID}::airdrop::new_airdrop`,
    typeArguments: [COIN_TYPE_ARGUMENT],
  });

  tx.transferObjects([cap], tx.pure.address(signer_address));

  let result = await client.signAndExecuteTransaction({
      signer: keypair,
      transaction: tx,
      options: {
        showObjectChanges: true,
      }
    });

  let airdrop_id = (result.objectChanges?.find(
    (change) =>
      change.type === "created" &&
      typeof change.objectType === "string" &&
      change.objectType.includes("airdrop::AirDrop") &&
      "objectId" in change
  ) as Extract<SuiObjectChange, { type: "created"; objectId: string }>)?.objectId ?? "";
  let airdrop_admin_cap = (result.objectChanges?.find(
    (change) =>
      change.type === "created" &&
      typeof change.objectType === "string" &&
      change.objectType.includes("airdrop::AdminCap") &&
      "objectId" in change
  ) as Extract<SuiObjectChange, { type: "created"; objectId: string }>)?.objectId ?? "";

  let totalClaimsToAdd = airdropData.length;

  console.log("Airdrop ID: ", airdrop_id);

  await waitForInput(
    `Need to add ${totalClaimsToAdd} claims. Press enter to continue...`
  );

  while (totalClaimsToAdd > 0) {
    let tx = new Transaction();
    tx.setSender(signer_address);

    const claimsToAdd = totalClaimsToAdd < 100 ? totalClaimsToAdd : 100;

    const claims = airdropData.splice(0, claimsToAdd);

    const addresses = claims.map((c) => c.address);
    const amounts = claims.map((c) => c.amount * 100000000);

    const totalAmountCreated = amounts.reduce(
      (acc, amount) => acc + Number(amount),
      0
    );

    await new Promise((resolve) => setTimeout(resolve, 4000));

    addresses.map((address) => {
      if (!isValidSuiAddress(address)) {
        console.error(`Invalid address: ${address}`);
        throw new Error(`Invalid address: ${address}`);
      }
    });

    tx.moveCall({
      target: `${AIRDROP_PACKAGE_ID}::airdrop::add_claims`,
      arguments: [
        tx.object(airdrop_id), 
        tx.object(airdrop_admin_cap), 
        tx.pure.vector("address", addresses), 
        tx.pure.vector("u64", amounts),
        coinWithBalance({
          balance: totalAmountCreated,
          type: COIN_TYPE_ARGUMENT,
          useGasCoin: true,
        })
      ], 
      typeArguments: [COIN_TYPE_ARGUMENT],
    });

    tx.setGasBudget(10000000000);

    totalClaimsToAdd -= addresses.length;

    const txResult = await client.devInspectTransactionBlock({
      sender: signer_address,
      transactionBlock: tx,
    });

    let gasUsed = txResult.effects.gasUsed;

    let total_gas_fees =
      Number(gasUsed.computationCost) + Number(gasUsed.storageCost);

    let balance = await client.getBalance({
      owner: signer_address,
    });

    if (Number(balance.totalBalance) < total_gas_fees) {
      await waitForInput(
        `Insufficient funds. Need ${total_gas_fees} but only have ${balance}. Send Sui to ${signer_address}. Press enter to continue...`
      );
    }

    process.stdout.write(
      `remaining: ${totalClaimsToAdd}\r`
      );

    try {
      const result = await client.signAndExecuteTransaction({
        signer: keypair,
        transaction: tx,
      });
    } catch (error) {
      console.error("Error executing transaction:", error);
      await waitForInput(
        `Transaction failed. Press enter to continue...`
      );
      continue;
    }
  }

  console.log("Airdrop successfully created at: ", airdrop_id);

  process.exit(0);
}

// Run the script
main().catch((e) => {
  console.error("Script failed:", e);
  process.exit(1);
});
