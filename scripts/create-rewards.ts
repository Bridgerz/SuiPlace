#!/usr/bin/env ts-node
import * as dotenv from "dotenv";
dotenv.config();

import { SuiClient } from "@mysten/sui/client";
import { isValidSuiAddress } from "@mysten/sui/utils";
import { Transaction } from "@mysten/sui/transactions";
import { Ed25519Keypair } from "@mysten/sui/keypairs/ed25519";
import * as fs from "fs";
import * as path from "path";

// ----------------- main -----------------
async function main() {
  const RPC_URL = process.env.RPC_URL!;
  const PRIVATE_KEY_BASE64 = process.env.PRIVATE_KEY_BASE64!;
  const PACKAGE_ID = process.env.PACKAGE_ID!; // package that contains `rewards`
  const CANVAS_ADMIN_CAP = process.env.CANVAS_ADMIN_CAP!; // CanvasAdminCap object id

  if (!RPC_URL || !PRIVATE_KEY_BASE64 || !PACKAGE_ID || !CANVAS_ADMIN_CAP) {
    throw new Error(
      "Missing required env: RPC_URL, PRIVATE_KEY_BASE64, PACKAGE_ID, CANVAS_ADMIN_CAP"
    );
  }

  const client = new SuiClient({ url: RPC_URL });
  const keypair = Ed25519Keypair.fromSecretKey(PRIVATE_KEY_BASE64);
  const signerAddress = keypair.getPublicKey().toSuiAddress();
  if (!isValidSuiAddress(signerAddress))
    throw new Error("Signer address invalid");
  console.log("Using signer:", signerAddress);

  const rewardsData = JSON.parse(
    fs.readFileSync(path.resolve(__dirname, "reward.json"), "utf8")
  );
  const BATCH_LIMIT = 500;

  // 1) Ensure reward wheel exists
  if (!rewardsData.wheelId) {
    console.log("No wheelId found in reward.json, creating a new RewardWheel…");
    const tx = new Transaction();
    tx.setSender(signerAddress);

    // Build an empty VecMap<String, String> via move call
    const emptyMeta = tx.moveCall({
      target: "0x2::vec_map::empty",
      typeArguments: ["0x1::string::String", "0x1::string::String"],
    });

    tx.moveCall({
      target: `${PACKAGE_ID}::rewards::create_reward_wheel`,
      arguments: [tx.object(CANVAS_ADMIN_CAP), emptyMeta],
    });

    tx.setGasBudget(2_000_000_000);

    const result = await client.signAndExecuteTransaction({
      signer: keypair,
      transaction: tx,
      options: { showObjectChanges: true },
    });

    const changes = (result as any).objectChanges as any[] | undefined;
    const createdWheel = changes?.find(
      (c: any) =>
        c.type === "created" &&
        typeof c.objectType === "string" &&
        c.objectType.endsWith("::rewards::RewardWheel")
    );

    if (!createdWheel) {
      throw new Error("Failed to detect created RewardWheel in object changes");
    }

    rewardsData.wheelId = (createdWheel as any).objectId as string;
    fs.writeFileSync(
      path.resolve(__dirname, "reward.json"),
      JSON.stringify(rewardsData, null, 2) + "\n",
      "utf8"
    );
    console.log("Created RewardWheel:", rewardsData.wheelId);
  } else {
    console.log("Using existing RewardWheel:", rewardsData.wheelId);
  }

  const wheelId = rewardsData.wheelId!;

  // add some delay between creating the wheel and adding the rewards
  await new Promise((resolve) => setTimeout(resolve, 2000));

  // 2) Iterate rewards and add by value entries
  for (const reward of rewardsData.rewards) {
    const coinType = reward.type;
    const valueEntries = reward.values || [];

    for (let idx = 0; idx < valueEntries.length; idx++) {
      const entry = valueEntries[idx];
      if (entry.added) {
        continue;
      }

      const amount = Number(entry.amount);
      const value = BigInt(entry.value);
      if (amount <= 0 || value <= BigInt(0)) {
        console.log(
          `Skipping invalid entry for ${reward.type} at index ${idx}`
        );
        entry.added = true;
        fs.writeFileSync(
          path.resolve(__dirname, "reward.json"),
          JSON.stringify(rewardsData, null, 2) + "\n",
          "utf8"
        );
        continue;
      }

      let addedSoFar = Number((entry as any).addedCount || 0);
      if (addedSoFar >= amount) {
        entry.added = true;
        fs.writeFileSync(
          path.resolve(__dirname, "reward.json"),
          JSON.stringify(rewardsData, null, 2) + "\n",
          "utf8"
        );
        continue;
      }

      console.log(
        `Adding rewards for type=${coinType}, value=${entry.value}, amount=${amount}, alreadyAdded=${addedSoFar}`
      );

      while (addedSoFar < amount) {
        const remaining = amount - addedSoFar;
        const batchSize = Math.min(remaining, BATCH_LIMIT);

        const tx = new Transaction();
        tx.setSender(signerAddress);

        // if coin is Sui, we need to get a gas coin
        let gasCoin: any = null;
        if (coinType === "0x2::sui::SUI") {
          const allCoins = await client.getCoins({
            owner: signerAddress,
            coinType: "0x2::sui::SUI",
          });
          // get largest coin object ID
          gasCoin = allCoins.data.sort(
            (a, b) => Number(b.balance) - Number(a.balance)
          )[1];

          if (gasCoin) {
            tx.setGasPayment([
              {
                objectId: gasCoin.coinObjectId,
                version: gasCoin.version,
                digest: gasCoin?.digest,
              },
            ]);
          }
        }

        // get coin object from connected wallet
        const coins = await client.getAllCoins({ owner: signerAddress });
        const coinId = coins.data.find(
          (c) =>
            c.coinType === coinType && c.coinObjectId !== gasCoin?.coinObjectId
        );
        if (!coinId) {
          throw new Error(`No coin of type ${coinType} found for splitting`);
        }

        // build vector of reward objects using splitCoins (bounded by BATCH_LIMIT)
        const splitAmts = new Array(batchSize).fill(Number(value));
        const coinsOut = tx.splitCoins(coinId.coinObjectId, splitAmts);

        // Call add_rewards<T>
        tx.moveCall({
          target: `${PACKAGE_ID}::rewards::add_rewards_v2`,
          arguments: [
            tx.object(wheelId),
            tx.object(CANVAS_ADMIN_CAP),
            tx.makeMoveVec({
              type: `0x2::coin::Coin<${coinType}>`,
              elements: [...coinsOut],
            }),
            tx.makeMoveVec({
              type: "u64",
              elements: [...splitAmts],
            }),
          ],
          typeArguments: [`0x2::coin::Coin<${coinType}>`],
        });

        tx.setGasBudget(5000000000);

        const res = await client.signAndExecuteTransaction({
          signer: keypair,
          transaction: tx,
          options: { showObjectChanges: true, showEffects: true },
        });
        if (res.effects?.status.status === "failure")
          throw new Error(res.effects?.status.error);

        console.log(
          `  ✅ batch size=${batchSize} for type=${coinType}, digest=${res.digest}`
        );

        // Update progress for idempotency
        addedSoFar += batchSize;
        (entry as any).addedCount = addedSoFar;
        fs.writeFileSync(
          path.resolve(__dirname, "reward.json"),
          JSON.stringify(rewardsData, null, 2) + "\n",
          "utf8"
        );
        await new Promise((resolve) => setTimeout(resolve, 2000));
      }

      // All batches for this entry completed
      entry.added = true;
      fs.writeFileSync(
        path.resolve(__dirname, "reward.json"),
        JSON.stringify(rewardsData, null, 2) + "\n",
        "utf8"
      );
    }
  }

  console.log("All rewards processed.");
}

main().catch((e) => {
  console.error("Script failed:", e);
  process.exit(1);
});
