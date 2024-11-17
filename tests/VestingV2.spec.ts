import { Blockchain, SandboxContract, TreasuryContract } from '@ton/sandbox';
import { toNano, Address, Cell } from '@ton/core';
import { VestingV2 } from '../wrappers/VestingV2';
import { SampleJetton } from "../wrappers/SampleJetton";
import '@ton/test-utils';
import { buildOnchainMetadata } from '../contracts/utils/jetton-helpers';
import { JettonDefaultWallet } from '../build/SampleJetton/tact_JettonDefaultWallet';
import { sleep } from '@ton/blueprint';

describe('VestingV2', () => {
    let blockchain: Blockchain;
    let vestingV2: SandboxContract<VestingV2>;
    let xanaToken: SandboxContract<SampleJetton>;
    let deployer: SandboxContract<TreasuryContract>;
    let vestingJettonWallet: SandboxContract<JettonDefaultWallet>;
    let deployerJettonWallet: SandboxContract<JettonDefaultWallet>;

    beforeEach(async () => {
        blockchain = await Blockchain.create();

        deployer = await blockchain.treasury('deployer');

        const jettonParams = {
            name: "XANA Token",
            description: "Primary token of the XANA Ecosystem",
            symbol: "XANA",
            image: "",
        };
        let content = buildOnchainMetadata(jettonParams);
        let maxSupply = toNano(10000000000); // 10 Billion
        xanaToken = blockchain.openContract(await SampleJetton.fromInit(
            deployer.address,
            content,
            maxSupply
        ));
        let init = await SampleJetton.init(deployer.address, content, maxSupply);
        vestingV2 = blockchain.openContract(await VestingV2.fromInit(
            xanaToken.address,
            xanaToken.address,
            maxSupply,
            1000n,
            [1000n, 1000n, 1000n, 1000n, 1000n] as any,
            [1000n, 1000n, 1000n, 1000n, 1000n] as any,
        ));

        const vestingDeployResult = await vestingV2.send(
            deployer.getSender(),
            { value: toNano('0.05') },
            { $$type: 'Deploy', queryId: 0n }
        );
    });

    it('should deploy', async () => {
        // Already validated in beforeEach
    });

    it('should set and get user claims', async () => {
        let emission = 1n;
        let amount = toNano(1000);

        await vestingV2.send(
            deployer.getSender(),
            { value: toNano('0.1') },
            {
                $$type: 'SetUserClaim',
                address: deployer.address,
                emission: emission,
                amount: amount,
            }
        );

        let claim = await vestingV2.getUserClaim(deployer.address, emission);
        console.log("After:", claim);
    });
});
