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

contract VestingV2 with Deployable, OwnableTransferable {
    owner: Address;
    xanaToken: Address;

    decimals: Int;
    vestingName: String;

    users: map<Address, User>;
    userClaims: map<Int, Claimed>;

    init(xanaTokenAddress: Address) {
        self.owner = sender();
        self.xanaToken = xanaTokenAddress;

        self.decimals = 20;
        self.vestingName = "seed";
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

    // receive(msg: ChangeOwner) is added automatically to transfer ownership
    // get fun owner(): Address is added automatically to query who the owner is
}