// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import {Vm} from "forge-std/Vm.sol";
import {BatchCallAndSponsor} from "../src/BatchCallAndSponsor.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

contract MockERC20 is ERC20 {
    constructor() ERC20("Mock Token", "MOCK") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract BatchCallAndSponsorScript is Script {
    // EOA with private key from .env
    uint256 EOA_PK;
    address payable EOA_ADDRESS;
    
    // Sponsor with private key from .env
    uint256 SPONSOR_PK;
    address payable SPONSOR_ADDRESS;

    // The contract that Alice will delegate execution to.
    BatchCallAndSponsor public implementation;

    // ERC-20 token contract for minting test tokens.
    MockERC20 public token;

    function setUp() public {
        // Load private keys from .env
        EOA_PK = vm.envUint("EOA_PK");
        SPONSOR_PK = vm.envUint("SPONSOR_PK");
        
        // Derive addresses from private keys
        EOA_ADDRESS = payable(vm.addr(EOA_PK));
        SPONSOR_ADDRESS = payable(vm.addr(SPONSOR_PK));
        
        console.log("EOA Address:", EOA_ADDRESS);
        console.log("Sponsor Address:", SPONSOR_ADDRESS);
    }
    
    function run() external {
        // Start broadcasting transactions with EOA's private key.
        vm.startBroadcast(EOA_PK);

        // Deploy the delegation contract (Alice will delegate calls to this contract).
        implementation = new BatchCallAndSponsor();

        // Deploy an ERC-20 token contract where Alice is the minter.
        token = new MockERC20();

        // // Fund accounts
        token.mint(EOA_ADDRESS, 1000e18);

        vm.stopBroadcast();

        // Perform direct execution
        performDirectExecution();

        // Perform sponsored execution
        performSponsoredExecution();
    }

    function performDirectExecution() internal {
        BatchCallAndSponsor.Call[] memory calls = new BatchCallAndSponsor.Call[](2);

        // ETH transfer (smaller amount to avoid OutOfFunds error)
        calls[0] = BatchCallAndSponsor.Call({to: SPONSOR_ADDRESS, value: 0.001 ether, data: ""}); // Use 0.001 ETH instead of 1 ETH

        // Token transfer
        calls[1] = BatchCallAndSponsor.Call({
            to: address(token),
            value: 0,
            data: abi.encodeCall(ERC20.transfer, (SPONSOR_ADDRESS, 100e18))
        });

        vm.signAndAttachDelegation(address(implementation), EOA_PK);
        vm.startPrank(EOA_ADDRESS);
        BatchCallAndSponsor(EOA_ADDRESS).execute(calls);
        vm.stopPrank();

        console.log("Sponsor's balance after direct execution:", SPONSOR_ADDRESS.balance);
        console.log("Sponsor's token balance after direct execution:", token.balanceOf(SPONSOR_ADDRESS));
    }

    function performSponsoredExecution() internal {
        console.log("Sending 1 ETH from EOA to a random address, the transaction is sponsored by the Sponsor");

        BatchCallAndSponsor.Call[] memory calls = new BatchCallAndSponsor.Call[](1);
        address recipient = makeAddr("recipient");
        calls[0] = BatchCallAndSponsor.Call({to: recipient, value: 0.001 ether, data: ""}); // Use 0.001 ETH instead of 1 ETH

        // EOA signs a delegation allowing `implementation` to execute transactions on their behalf.
        Vm.SignedDelegation memory signedDelegation = vm.signDelegation(address(implementation), EOA_PK);

        // Sponsor attaches the signed delegation from EOA and broadcasts it.
        vm.startBroadcast(SPONSOR_PK);
        vm.attachDelegation(signedDelegation);

        // Verify that EOA's account now temporarily behaves as a smart contract.
        bytes memory code = address(EOA_ADDRESS).code;
        require(code.length > 0, "no code written to EOA");
        // console.log("Code on Alice's account:", vm.toString(code));

        bytes memory encodedCalls = "";
        for (uint256 i = 0; i < calls.length; i++) {
            encodedCalls = abi.encodePacked(encodedCalls, calls[i].to, calls[i].value, calls[i].data);
        }
        bytes32 digest = keccak256(abi.encodePacked(BatchCallAndSponsor(EOA_ADDRESS).nonce(), encodedCalls));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(EOA_PK, MessageHashUtils.toEthSignedMessageHash(digest));
        bytes memory signature = abi.encodePacked(r, s, v);

        // As Sponsor, execute the transaction via EOA's temporarily assigned contract.
        BatchCallAndSponsor(EOA_ADDRESS).execute(calls, signature);

        vm.stopBroadcast();

        console.log("Recipient balance after sponsored execution:", recipient.balance);
    }
}
