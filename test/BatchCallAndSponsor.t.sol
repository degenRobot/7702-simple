// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console2} from "forge-std/Test.sol";
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

contract BatchCallAndSponsorTest is Test {
    // EOA with private key from .env
    uint256 EOA_PK;
    address payable EOA_ADDRESS;
    
    // Sponsor with private key from .env
    uint256 SPONSOR_PK;
    address payable SPONSOR_ADDRESS;

    // The contract that EOA will delegate execution to.
    BatchCallAndSponsor public implementation;

    // ERC-20 token contract for minting test tokens.
    MockERC20 public token;

    event CallExecuted(address indexed to, uint256 value, bytes data);
    event BatchExecuted(uint256 indexed nonce, BatchCallAndSponsor.Call[] calls);

    function setUp() public {
        // Load private keys from .env
        EOA_PK = vm.envUint("EOA_PK");
        SPONSOR_PK = vm.envUint("SPONSOR_PK");
        
        // Derive addresses from private keys
        EOA_ADDRESS = payable(vm.addr(EOA_PK));
        SPONSOR_ADDRESS = payable(vm.addr(SPONSOR_PK));
        
        console2.log("EOA Address:", EOA_ADDRESS);
        console2.log("Sponsor Address:", SPONSOR_ADDRESS);
        // Deploy the delegation contract (EOA will delegate calls to this contract).
        implementation = new BatchCallAndSponsor();

        // Deploy an ERC-20 token contract where EOA is the minter.
        token = new MockERC20();

        // Fund accounts
        vm.deal(EOA_ADDRESS, 10 ether);
        token.mint(EOA_ADDRESS, 1000e18);
    }

    function testDirectExecution() public {
        console2.log("Sending 0.0001 ETH from EOA to Sponsor and transferring 100 tokens to Sponsor in a single transaction");
        
        // Record initial balances
        uint256 sponsorInitialBalance = SPONSOR_ADDRESS.balance;
        uint256 sponsorInitialTokenBalance = token.balanceOf(SPONSOR_ADDRESS);
        uint256 eoaInitialBalance = EOA_ADDRESS.balance;
        
        console2.log("Initial EOA balance:", eoaInitialBalance);
        console2.log("Initial Sponsor balance:", sponsorInitialBalance);
        
        BatchCallAndSponsor.Call[] memory calls = new BatchCallAndSponsor.Call[](2);

        // ETH transfer
        calls[0] = BatchCallAndSponsor.Call({to: SPONSOR_ADDRESS, value: 0.0001 ether, data: ""});

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
        
        // Check balance changes
        assertEq(SPONSOR_ADDRESS.balance - sponsorInitialBalance, 1 ether, "Sponsor ETH balance did not increase by expected amount");
        assertEq(token.balanceOf(SPONSOR_ADDRESS) - sponsorInitialTokenBalance, 100e18, "Sponsor token balance did not increase by expected amount");
    }

    function testSponsoredExecution() public {
        console2.log("Sending 1 ETH from EOA to a random address while the transaction is sponsored by Sponsor");

        BatchCallAndSponsor.Call[] memory calls = new BatchCallAndSponsor.Call[](1);
        address recipient = makeAddr("recipient");
        
        // Record initial balances
        uint256 recipientInitialBalance = recipient.balance;
        uint256 eoaInitialBalance = EOA_ADDRESS.balance;
        
        console2.log("Initial EOA balance:", eoaInitialBalance);
        console2.log("Initial recipient balance:", recipientInitialBalance);

        calls[0] = BatchCallAndSponsor.Call({to: recipient, value: 1 ether, data: ""});

        // EOA signs a delegation allowing `implementation` to execute transactions on their behalf.
        Vm.SignedDelegation memory signedDelegation = vm.signDelegation(address(implementation), EOA_PK);

        // Sponsor attaches the signed delegation from EOA and broadcasts it.
        vm.startBroadcast(SPONSOR_PK);
        vm.attachDelegation(signedDelegation);

        // Verify that EOA's account now temporarily behaves as a smart contract.
        bytes memory code = address(EOA_ADDRESS).code;
        require(code.length > 0, "no code written to EOA");

        bytes memory encodedCalls = "";
        for (uint256 i = 0; i < calls.length; i++) {
            encodedCalls = abi.encodePacked(encodedCalls, calls[i].to, calls[i].value, calls[i].data);
        }

        bytes32 digest = keccak256(abi.encodePacked(BatchCallAndSponsor(EOA_ADDRESS).nonce(), encodedCalls));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(EOA_PK, MessageHashUtils.toEthSignedMessageHash(digest));
        bytes memory signature = abi.encodePacked(r, s, v);

        // Expect the event. The first parameter should be SPONSOR_ADDRESS.
        vm.expectEmit(true, true, true, true);
        emit BatchCallAndSponsor.CallExecuted(SPONSOR_ADDRESS, calls[0].to, calls[0].value, calls[0].data);

        // As Sponsor, execute the transaction via EOA's temporarily assigned contract.
        BatchCallAndSponsor(EOA_ADDRESS).execute(calls, signature);

        vm.stopBroadcast();

        // Check balance change
        assertEq(recipient.balance - recipientInitialBalance, 1 ether, "Recipient ETH balance did not increase by expected amount");
    }

    function testWrongSignature() public {
        console2.log("Test wrong signature: Execution should revert with 'Invalid signature'.");
        BatchCallAndSponsor.Call[] memory calls = new BatchCallAndSponsor.Call[](1);
        calls[0] = BatchCallAndSponsor.Call({
            to: address(token),
            value: 0,
            data: abi.encodeCall(MockERC20.mint, (SPONSOR_ADDRESS, 50))
        });

        // Build the encoded call data.
        bytes memory encodedCalls = "";
        for (uint256 i = 0; i < calls.length; i++) {
            encodedCalls = abi.encodePacked(encodedCalls, calls[i].to, calls[i].value, calls[i].data);
        }

        // EOA signs a delegation allowing `implementation` to execute transactions on their behalf.
        Vm.SignedDelegation memory signedDelegation = vm.signDelegation(address(implementation), EOA_PK);

        // Sponsor attaches the signed delegation from EOA and broadcasts it.
        vm.startBroadcast(SPONSOR_PK);
        vm.attachDelegation(signedDelegation);

        bytes32 digest = keccak256(abi.encodePacked(BatchCallAndSponsor(EOA_ADDRESS).nonce(), encodedCalls));
        // Sign with the wrong key (Sponsor's instead of EOA's).
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(SPONSOR_PK, MessageHashUtils.toEthSignedMessageHash(digest));
        bytes memory signature = abi.encodePacked(r, s, v);

        vm.expectRevert("Invalid signature");
        BatchCallAndSponsor(EOA_ADDRESS).execute(calls, signature);
        vm.stopBroadcast();
    }

    function testReplayAttack() public {
        console2.log("Test replay attack: Reusing the same signature should revert.");
        BatchCallAndSponsor.Call[] memory calls = new BatchCallAndSponsor.Call[](1);
        calls[0] = BatchCallAndSponsor.Call({
            to: address(token),
            value: 0,
            data: abi.encodeCall(MockERC20.mint, (SPONSOR_ADDRESS, 30))
        });

        // Build encoded call data.
        bytes memory encodedCalls = "";
        for (uint256 i = 0; i < calls.length; i++) {
            encodedCalls = abi.encodePacked(encodedCalls, calls[i].to, calls[i].value, calls[i].data);
        }

        // EOA signs a delegation allowing `implementation` to execute transactions on their behalf.
        Vm.SignedDelegation memory signedDelegation = vm.signDelegation(address(implementation), EOA_PK);

        // Sponsor attaches the signed delegation from EOA and broadcasts it.
        vm.startBroadcast(SPONSOR_PK);
        vm.attachDelegation(signedDelegation);

        uint256 nonceBefore = BatchCallAndSponsor(EOA_ADDRESS).nonce();
        bytes32 digest = keccak256(abi.encodePacked(nonceBefore, encodedCalls));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(EOA_PK, MessageHashUtils.toEthSignedMessageHash(digest));
        bytes memory signature = abi.encodePacked(r, s, v);

        // First execution: should succeed.
        BatchCallAndSponsor(EOA_ADDRESS).execute(calls, signature);
        vm.stopBroadcast();

        // Attempt a replay: reusing the same signature should revert because nonce has incremented.
        vm.expectRevert("Invalid signature");
        BatchCallAndSponsor(EOA_ADDRESS).execute(calls, signature);
    }
}
