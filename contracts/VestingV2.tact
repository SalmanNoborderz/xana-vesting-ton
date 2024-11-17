import "@stdlib/deploy";
import "@stdlib/ownable";
import "./utils/Arrays.tact";
import "./SampleJetton.tact";

struct Claimed {
    user: Address;
    claimEmission: Int;
    claimedAmount: Int;
}

struct User {
    valid: Bool;
    totalAmount: Int;
    claimedAmount: Int;
    claimedEmissions: Int;
}


struct EmissionTimes {
    emissionStart: Int;
    emissionEnd: Int;
    emissionDays: Int;
}

message SetVestingName {
    name: String;
}

message SetDecimals {
    decimals: Int;
}

message SetUser {
    valid: Bool;
    address: Address;
    totalAmount: Int;
    claimedAmount: Int;
    claimedEmissions: Int;
}

message DeleteUser {
    address: Address;
}

message SetUserClaim {
    address: Address;
    emission: Int;
    amount: Int;
}

message SetTotalV1Emissions {
    emissions: Int;
}

message UserClaimable {
    daysToBeClaimed: Int;
    daysAfterRelease: Int;
    userAmountPerClaim: Int;
    amountToBeClaimed: Int;
}

message Claim {
    beneficiary: Address;
}

message EmergencyWithdraw {
    to: Address;
    amount: Int;
}

contract VestingV2 with Deployable, OwnableTransferable {
    owner: Address;
    xanaToken: Address;

    decimals: Int;
    vestingName: String;
    
    limit: Array;
    reward: Array;
    maxSupply: Int;
    firstRelease: Int;

    vestingV1: Address;
    totalV1Emissions: Int;

    users: map<Address, User>;
    userClaims: map<Int, Claimed>;

    init(xanaTokenAddress: Address, vestingV1Address: Address, maxSupply: Int, firstRelease: Int, limit: Array, reward: Array) {
        self.owner = sender();
        self.xanaToken = xanaTokenAddress;

        self.limit = limit;
        self.decimals = 20;
        self.reward = reward;
        self.vestingName = "seed";
        self.totalV1Emissions = 0;
        self.maxSupply = maxSupply;
        self.firstRelease = firstRelease;
        self.vestingV1 = vestingV1Address;
    }

    receive(msg: SetVestingName) {
        self.requireOwner();
        self.vestingName = msg.name;
    }

    receive(msg: SetDecimals) {
        self.requireOwner();
        self.decimals = msg.decimals;
    }

    receive(msg: SetUser) {
        self.requireOwner();
        self.users.set(msg.address, User{
            valid: msg.valid,
            totalAmount: msg.totalAmount,
            claimedAmount: msg.claimedAmount,
            claimedEmissions: msg.claimedEmissions
        });
    }

    receive(msg: DeleteUser) {
        self.requireOwner();
        self.users.set(msg.address, emptyMap());
    }

    receive(msg: SetTotalV1Emissions) {
        if (self.vestingV1 != sender()) {
            self.requireOwner();
        }
        self.totalV1Emissions = msg.emissions;
    }

    fun toInt(str: String): Int {
        // Cast the String as a Slice for parsing
        let string: Slice = str.asSlice();

        // A variable to store the accumulated number
        let acc: Int = 0;

        // Loop until the String is empty
        while (!string.empty()) {
            let char: Int = string.loadUint(8); // load 8 bits (1 byte) from the Slice
            acc = (acc * 10) + (char - 48);     // using ASCII table to get numeric value
            // Note, that this approach would produce unexpected results
            // when the starting String contains non-numeric characters!
        }

        // Produce the resulting number
        return acc;
    }

    fun generateKey(user: Address, emission: Int): Int {
        // Concatenate the address and emission to get a unique identifier
        let key: StringBuilder = beginString()
        .concat(user.toString())
        .concat(emission.toString());
        return self.toInt(key.toString());
    }

    receive(msg: SetUserClaim) {
        self.requireOwner();
        let key = self.generateKey(msg.address, msg.emission);
        self.userClaims.set(key, Claimed{
            user: msg.address,
            claimEmission: msg.emission,
            claimedAmount: msg.amount
        });
    }

    fun getUserClaimable(beneficiary: Address, totalAmountPerClaim: Int, emissionStart: Int, emissionDays: Int, emission: Int): UserClaimable {
        let user: User = self.users.get(beneficiary)!!;
        let emissionKey = self.generateKey(beneficiary, emission);
        let claimed: Int = self.userClaims.get(emissionKey)!!.claimedAmount;
        let userPercentage: Int = (user.totalAmount * 100 * pow(10, self.decimals)) / self.maxSupply;
        let userAmountPerClaim: Int = (totalAmountPerClaim * userPercentage) / pow(10, self.decimals);
        let daysAfterRelease: Int = (now() - emissionStart) / 86400 > emissionDays ? emissionDays : (now() - emissionStart) / 86400;
        let daysToBeClaimed = daysAfterRelease - claimed;
        return UserClaimable{
            daysToBeClaimed: daysToBeClaimed,
            daysAfterRelease: daysAfterRelease,
            userAmountPerClaim: userAmountPerClaim,
            amountToBeClaimed: userAmountPerClaim * daysToBeClaimed
        };
    }

    fun nextEmissionTimes(_emission: Int): EmissionTimes {
        let emissionEnd: Int = 0;
        let emissionDays: Int = 0;
        let emissionStart: Int = self.firstRelease;

        let i: Int = 0;
        while (i <= _emission) {
            if (i !=0) {emissionStart = emissionStart + (self.limit.m.get(i)!! * 86400)}

            if (i == self.limit.length) {
                emissionEnd = emissionStart + (self.limit.m.get(i)!! * 86400);
            } else {
                emissionEnd = emissionStart + (self.limit.m.get(i+1)!! * 86400);
            }

            i = i + 1;
        }
        emissionDays = (emissionEnd - emissionStart) / 86400;
        return EmissionTimes{
            emissionStart: emissionStart,
            emissionEnd: emissionEnd,
            emissionDays: emissionDays
        };
    }

    fun transferJettons(destination: Address, amount: Int, responseDestination: Address) {
        let ctx: Context = context();

        // Gas checks
        let fwdFee: Int = ctx.readForwardFee();
        let final: Int = 2 * ton("0.01") + fwdFee;
        require(ctx.value > final, "Invalid value!!"); 

        // Initialize the wallet
        let walletInit: StateInit = initOf JettonDefaultWallet(self.xanaToken, myAddress());

        // Send the token transfer
        send(SendParameters{
            to: contractAddress(walletInit),
            value: ton("0.05"),
            bounce: false,
            body: TokenTransfer{
                queryId: now(), // Use a proper query ID
                amount: amount,
                destination: destination,
                response_destination: myAddress(),
                custom_payload: null,
                forward_ton_amount: ton("0.01"),
                forward_payload: emptySlice()
            }.toCell()
        });
    }

    receive(msg: Claim) {
        let beneficiary: Address = msg.beneficiary;
        if (self.owner != sender()) {
            beneficiary = sender();
        }

        let amountToRelease: Int = 0;
        let user: User = self.users.get(beneficiary)!!;

        let i: Int = 0;
        while (i < self.totalV1Emissions) {
            let emissionTimes: EmissionTimes = self.nextEmissionTimes(i);
            if (emissionTimes.emissionStart <= now()) {
                let emissionPercentage: Int = self.reward.m.get(i)!!;
                let releasedAmount: Int = (emissionPercentage * self.maxSupply) / pow(10, self.decimals);
                let totalAmountPerClaim: Int = releasedAmount / emissionTimes.emissionDays;
                let claimableData: UserClaimable = self.getUserClaimable(beneficiary, totalAmountPerClaim, emissionTimes.emissionStart, emissionTimes.emissionDays, i);

                if (releasedAmount > 0 && claimableData.amountToBeClaimed > 0) {
                    if (emissionTimes.emissionDays == claimableData.daysAfterRelease) {
                        let missed: Int = ((emissionPercentage * user.totalAmount) / pow(10, self.decimals)) - (claimableData.daysAfterRelease * claimableData.userAmountPerClaim);
                        amountToRelease += (claimableData.daysToBeClaimed * claimableData.userAmountPerClaim) + missed;
                    } else {
                        amountToRelease += claimableData.amountToBeClaimed;
                    }
                }

                self.userClaims.set(self.generateKey(beneficiary, i), Claimed{
                    user: beneficiary,
                    claimEmission: i,
                    claimedAmount: claimableData.daysToBeClaimed
                });
            }
            i += 1;
        }

        self.users.set(beneficiary, User{
            valid: user.valid,
            totalAmount: user.totalAmount,
            claimedAmount: user.claimedAmount + amountToRelease,
            claimedEmissions: self.totalV1Emissions
        });

        require(amountToRelease > 0, "Nothing to claim");
        self.transferJettons(beneficiary, amountToRelease, beneficiary);
    }

    receive(msg: EmergencyWithdraw) {
        self.requireOwner();
        self.transferJettons(msg.to, msg.amount, msg.to);
    }

    get fun UserClaim(user: Address, emission: Int): Claimed {
        let key = self.generateKey(user, emission);
        return self.userClaims.get(key)!!;
    }

    get fun GeneratedKey(user: Address, emission: Int): Int {
        return self.generateKey(user, emission);
    }

    get fun TotalEmissions(): Int {
        return self.totalV1Emissions;
    }

    // receive(msg: ChangeOwner) is added automatically to transfer ownership
    // get fun owner(): Address is added automatically to query who the owner is
}