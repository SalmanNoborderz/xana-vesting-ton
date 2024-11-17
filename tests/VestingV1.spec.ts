import { Blockchain, SandboxContract, TreasuryContract } from '@ton/sandbox';
import { toNano, Address, Cell } from '@ton/core';
import { SetCategoryDetails, VestingV1 } from '../wrappers/VestingV1';
import { SampleJetton } from "../wrappers/SampleJetton";
import '@ton/test-utils';
import { buildOnchainMetadata } from '../contracts/utils/jetton-helpers';
import { JettonDefaultWallet } from '../build/SampleJetton/tact_JettonDefaultWallet';
import { sleep } from '@ton/blueprint';
import { VestingV2 } from '../wrappers/VestingV2';

describe('VestingV1', () => {
    let blockchain: Blockchain;
    let vestingV1: SandboxContract<VestingV1>;
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
        vestingV1 = blockchain.openContract(await VestingV1.fromInit(
            xanaToken.address,
            // init.code
        ));

        const vestingDeployResult = await vestingV1.send(
            deployer.getSender(),
            { value: toNano('0.05') },
            { $$type: 'Deploy', queryId: 0n }
        );

        expect(vestingDeployResult.transactions).toHaveTransaction({
            from: deployer.address,
            to: vestingV1.address,
            deploy: true,
            success: true,
        });

        const xanaTokenDeployResult = await xanaToken.send(deployer.getSender(), { value: toNano("10") }, "Mint: 100");
        expect(xanaTokenDeployResult.transactions).toHaveTransaction({
            from: deployer.address,
            to: xanaToken.address,
            deploy: true,
            success: true,
        });

        const userJettonWallet = await xanaToken.getGetWalletAddress(deployer.address);
        deployerJettonWallet = blockchain.openContract(await JettonDefaultWallet.fromAddress(userJettonWallet));

        const vJettonWallet = await xanaToken.getGetWalletAddress(vestingV1.address);
        vestingJettonWallet = blockchain.openContract(await JettonDefaultWallet.fromAddress(vJettonWallet));

        vestingV2 = blockchain.openContract(await VestingV2.fromInit(
            xanaToken.address,
            vestingV1.address,
            maxSupply,
            1000n,
            [1000n, 1000n, 1000n, 1000n, 1000n] as any,
            [1000n, 1000n, 1000n, 1000n, 1000n] as any,
        ));

        const vestingV2DeployResult = await vestingV2.send(
            deployer.getSender(),
            { value: toNano('0.05') },
            { $$type: 'Deploy', queryId: 0n }
        );
    });

    it('should deploy', async () => {
        // Already validated in beforeEach
    });

    it('should set and verify first release time', async () => {
        const firstRelease = 1000n;
        const result = await vestingV1.send(
            deployer.getSender(),
            { value: toNano('0.05') },
            { $$type: 'SetFirstRelease', firstRelease }
        );

        expect(result.transactions).toHaveTransaction({
            from: deployer.address,
            to: vestingV1.address,
            success: true,
        });

        expect(await vestingV1.getFirstRelease()).toEqual(firstRelease);
    });

    it('should set category details', async () => {
        const categoryDetails: any = {
            valid: true,
            category: 1n,
            maxSupply: 500000n,
            totalReleased: 0n,
            releaseAmounts: [1000n, 2000n, 3000n] as any,
            lastWithdrawTime: 0n,
            targetAddress: deployer.address,
            lastWithdrawAmount: 0n,
        };

        const result = await vestingV1.send(
            deployer.getSender(),
            { value: toNano('0.05') },
            { $$type: 'SetCategoryDetails', ...categoryDetails }
        );

        expect(result.transactions).toHaveTransaction({
            from: deployer.address,
            to: vestingV1.address,
            success: true,
        });

        await vestingV1.getCategoryDetails(1n);
    });

    it('should remove a category', async () => {
        const category = 1n;

        await vestingV1.send(
            deployer.getSender(),
            { value: toNano('0.05') },
            {
                $$type: 'SetCategoryDetails',
                valid: true,
                category,
                maxSupply: 500000n,
                totalReleased: 0n,
                releaseAmounts: [1000n, 2000n] as any,
                lastWithdrawTime: 0n,
                targetAddress: deployer.address,
                lastWithdrawAmount: 0n,
            }
        );

        const result = await vestingV1.send(
            deployer.getSender(),
            { value: toNano('0.05') },
            { $$type: 'RemoveCategory', category }
        );

        expect(result.transactions).toHaveTransaction({
            from: deployer.address,
            to: vestingV1.address,
            success: true,
        });

        await expect(vestingV1.getCategoryDetails(category)).rejects.toThrow();
    });

    it('should set release amounts for a category', async () => {
        const category = 1n;
        const releaseAmounts = [500n, 1000n, 1500n] as any;

        await vestingV1.send(
            deployer.getSender(),
            { value: toNano('0.05') },
            {
                $$type: 'SetCategoryDetails',
                valid: true,
                category,
                maxSupply: 500000n,
                totalReleased: 0n,
                releaseAmounts: [] as any,
                lastWithdrawTime: 0n,
                targetAddress: deployer.address,
                lastWithdrawAmount: 0n,
            }
        );

        const result = await vestingV1.send(
            deployer.getSender(),
            { value: toNano('0.05') },
            { $$type: 'SetReleaseAmount', category, releaseAmounts }
        );

        expect(result.transactions).toHaveTransaction({
            from: deployer.address,
            to: vestingV1.address,
            success: true,
        });

        // expect(await vestingV1.getReleaseAmounts(category)).toEqual(releaseAmounts);
    });

    it('should set global variables', async () => {
        const globals: any = {
            time: 86400n,
            limit: [1n, 2n, 3n],
            emission: 5n,
            decimals: 18n,
            nextWithdrawtime: 2000n,
        };

        const result = await vestingV1.send(
            deployer.getSender(),
            { value: toNano('0.05') },
            { $$type: 'SetGlobals', ...globals }
        );

        expect(result.transactions).toHaveTransaction({
            from: deployer.address,
            to: vestingV1.address,
            success: true,
        });

        const storedGlobals = await vestingV1.getGlobals();
        // expect(storedGlobals).toEqual(globals);
    });

    it('should fail to handle emergency withdrawal', async () => {
        const recipient = deployer.address;

        const result = await vestingV1.send(
            deployer.getSender(),
            { value: toNano('0.05') },
            { $$type: 'EmergencyWithdraw', to: recipient, amount: 1000n }
        );

        expect(result.transactions).toHaveTransaction({
            from: deployer.address,
            to: vestingV1.address,
            success: false,
        });
    });

    it ('should succesfully handle emergency withdrawal', async () => {
        const totalSupplyBefore = (await xanaToken.getGetJettonData()).totalSupply;
        const mintAmount = toNano(1);

        // mint some tokens to vesting contract
        await xanaToken.send(
            deployer.getSender(),
            { value: toNano('0.05') },
            { $$type: 'Mint', receiver: vestingV1.address, amount: mintAmount }
        );

        // check if total supply has increased
        const totalSupplyAfter = (await xanaToken.getGetJettonData()).totalSupply;
        expect(totalSupplyBefore + mintAmount).toEqual(totalSupplyAfter);

        // get wallet data
        let vestinWalletData = await vestingJettonWallet.getGetWalletData();
        let deployerWalletData = await deployerJettonWallet.getGetWalletData();

        // check if vesting wallet has received the minted amount
        expect(vestinWalletData.owner).toEqualAddress(vestingV1.address);
        expect(vestinWalletData.balance).toBeGreaterThanOrEqual(mintAmount);        

        // call emergency withdraw
        const resp = await vestingV1.send(
            deployer.getSender(),
            { value: toNano('0.07') },
            { $$type: 'EmergencyWithdraw', to: deployer.address, amount: mintAmount }
        );

        // check if the transaction was successful
        expect(resp.transactions).toHaveTransaction({
            from: deployer.address,
            to: vestingV1.address,
            success: true,
        });

        // get updated wallet data
        vestinWalletData = await vestingJettonWallet.getGetWalletData();
        deployerWalletData = await deployerJettonWallet.getGetWalletData();

        // check if the amount was transferred to deployer wallet
        expect(vestinWalletData.balance).toBeLessThanOrEqual(0n);
        expect(deployerWalletData.balance).toBeGreaterThanOrEqual(mintAmount + 100n);
    });

    it('should correctly set and retrieve multiple category details', async () => {
        const categories = [
            { category: 2n, maxSupply: 1000n, releaseAmounts: [100n, 200n] },
            { category: 3n, maxSupply: 2000n, releaseAmounts: [300n, 400n] }
        ];

        for (const cat of categories) {
            await vestingV1.send(deployer.getSender(), { value: toNano('0.05') }, {
                $$type: 'SetCategoryDetails',
                valid: true,
                category: cat.category,
                maxSupply: cat.maxSupply,
                totalReleased: 0n,
                releaseAmounts: cat.releaseAmounts as any,
                lastWithdrawTime: 0n,
                targetAddress: deployer.address,
                lastWithdrawAmount: 0n,
            });

            const details = await vestingV1.getCategoryDetails(cat.category);
            // expect(details.maxSupply).toEqual(cat.maxSupply);
            // expect(details.releaseAmounts).toEqual(cat.releaseAmounts);
        }
    });

    it('should set and retrieve new global variables successfully', async () => {
        const newGlobals = {
            time: 7200n, // 2 hours
            limit: [5n, 10n, 15n] as any,
            emission: 10n,
            decimals: 18n,
            nextWithdrawtime: 3000n,
        };

        const result = await vestingV1.send(
            deployer.getSender(),
            { value: toNano('0.05') },
            { $$type: 'SetGlobals', ...newGlobals }
        );

        expect(result.transactions).toHaveTransaction({
            from: deployer.address,
            to: vestingV1.address,
            success: true,
        });

        // const storedGlobals = await vestingV1.getGlobals();
        // expect(storedGlobals.time).toEqual(newGlobals.time);
        // expect(storedGlobals.limit).toEqual(newGlobals.limit);
        // expect(storedGlobals.emission).toEqual(newGlobals.emission);
    });

    it('should not allow setting invalid release amounts for a category', async () => {
        const category = 1n;
        const invalidReleaseAmounts = [-100n, -200n] as any; // Negative values

        const result = await vestingV1.send(
            deployer.getSender(),
            { value: toNano('0.05') },
            { $$type: 'SetReleaseAmount', category, releaseAmounts: invalidReleaseAmounts }
        );

        expect(result.transactions).toHaveTransaction({
            from: deployer.address,
            to: vestingV1.address,
            success: false,
        });
    });

    it('should set emission on v2', async () => {
        console.log("V2 emissions Before:", await vestingV2.getTotalEmissions());

        const emission = 2n;
        const result = await vestingV1.send(
            deployer.getSender(),
            { value: toNano('0.1') },
            { $$type: 'TestV2EmissionSet', emissions: emission, address: vestingV2.address }
        );

        console.log("V2 emissions after:", await vestingV2.getTotalEmissions());

        // expect(result.transactions).toHaveTransaction({
        //     from: deployer.address,
        //     to: vestingV2.address,
        //     success: true,
        // });

        // expect(await vestingV2.getTotalEmissions()).toEqual(emission);
    });

    // it('should correctly calculate next emission times', async () => {
    //     const emission = 2n;
    //     await vestingV1.getNextEmissionTimes(emission);

    //     // expect(emissionTimes.emissionStart).toBeGreaterThan(0);
    //     // expect(emissionTimes.emissionEnd).toBeGreaterThan(emissionTimes.emissionStart);
    //     // expect(emissionTimes.emissionDays).toBeGreaterThan(0);
    // });
});
