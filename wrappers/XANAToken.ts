// TODO: possibly use this outside tests

import BN from "bn.js";
import { SmartContract } from "ton-contract-executor";
import { Address, beginCell, contractAddress, Slice, toNano, Cell } from "ton";

enum OPS {
    // Transfer = 0xf8a7ea5,
    // Transfer_notification = 0x7362d09c,
    // Internal_transfer = 0x178d4519,
    // Excesses = 0xd53276db,
    // Burn = 0x595f07bc,
    // Burn_notification = 0x7bdd97de,
    // ClaimRewards = 0x5a3e000,
    // ClaimRewardsNotification = 0x5a3e001,
    Mint = 21,
    InternalTransfer = 0x178d4519,
    Transfer = 0xf8a7ea5,
}

class WrappedSmartContract {
    contract: SmartContract;
    address: Address;

    constructor(contract: SmartContract, address: Address) {
        this.contract = contract;
        this.address = address;
    }

    // TODO extends typeof / instancetype
    static async create<T extends typeof WrappedSmartContract>(
        codeCell: any,
        dataCell: any
    ): Promise<InstanceType<T>> {
        const contract = await SmartContract.fromCell(codeCell, dataCell, {
            debug: true,
        });

        const stateInit = {
            code: codeCell,
            data: dataCell,
        };
        const ca = contractAddress(0, stateInit);
        contract.setC7Config({ myself: ca }); // TODO -> set the rest of the config

        return new this(contract, ca) as InstanceType<T>;
    }
}

export class JettonMinter extends WrappedSmartContract {
    async getWalletAddress(forTonWalletAddress: Address): Promise<Address> {
        const res = await this.contract.invokeGetMethod("get_wallet_address", [
            // TODO(sy) ['tvm.Slice', cellBoc] => also a less desired API (tonclient)
            {
                type: "cell_slice",
                value: beginCell()
                    .storeAddress(forTonWalletAddress)
                    .endCell()
                    .toBoc({ idx: false })
                    .toString("base64"),
            },
        ]);

        return (res.result[0] as unknown as Slice).loadAddress()!;
    }

    static mintBody(ownerAddress: Address, jettonValue: bigint): Cell {
        return beginCell()
            .storeUint(OPS.Mint, 32) // opcode (reference TODO)
            .storeUint(0, 64) // queryid
            .storeAddress(ownerAddress)
            .storeCoins(toNano(0.2)) // gas fee
            .storeRef(
                // internal transfer message
                beginCell()
                    .storeUint(OPS.InternalTransfer, 32)
                    .storeUint(0, 64)
                    .storeCoins(jettonValue)
                    .storeAddress(null) // TODO FROM?
                    .storeAddress(null) // TODO RESP?
                    .storeCoins(0)
                    .storeBit(false) // forward_payload in this slice, not separate cell
                    .endCell()
            )
            .endCell();
    }
}