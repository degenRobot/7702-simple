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

contract BatchCallAndSponsorV2 is BatchCallAndSponsor {
    string public constant VERSION = "V2";
    
    event V2ActionPerformed(address indexed sender, string action);
    
    function performV2Action(string calldata action) external {
        require(msg.sender == address(this), "Invalid authority");
        emit V2ActionPerformed(msg.sender, action);
    }
}

contract ReDelegateAuthorityScript is Script {
    uint256 EOA_PK;
    address payable EOA_ADDRESS;
    
    uint256 SPONSOR_PK;
    address payable SPONSOR_ADDRESS;

    BatchCallAndSponsor public implementation1;
    BatchCallAndSponsorV2 public implementation2;

    MockERC20 public token;

    function setUp() public {
        EOA_PK = vm.envUint("EOA_PK");
        SPONSOR_PK = vm.envUint("SPONSOR_PK");
        
        EOA_ADDRESS = payable(vm.addr(EOA_PK));
        SPONSOR_ADDRESS = payable(vm.addr(SPONSOR_PK));
        
        console.log("EOA Address:", EOA_ADDRESS);
        console.log("Sponsor Address:", SPONSOR_ADDRESS);
    }
    
    function run() external {
        vm.startBroadcast(EOA_PK);

        implementation1 = new BatchCallAndSponsor();
        console.log("First implementation deployed at:", address(implementation1));

        implementation2 = new BatchCallAndSponsorV2();
        console.log("Second implementation (V2) deployed at:", address(implementation2));

        token = new MockERC20();
        token.mint(EOA_ADDRESS, 1000e18);

        vm.stopBroadcast();

        console.log("\n--- Testing Initial Delegation ---");
        testInitialDelegation();

        console.log("\n--- Testing Re-Delegation ---");
        testReDelegation();
    }

    function testInitialDelegation() internal {
        BatchCallAndSponsor.Call[] memory calls = new BatchCallAndSponsor.Call[](1);
        
        calls[0] = BatchCallAndSponsor.Call({
            to: address(token),
            value: 0,
            data: abi.encodeCall(ERC20.transfer, (SPONSOR_ADDRESS, 50e18))
        });

        vm.signAndAttachDelegation(address(implementation1), EOA_PK);
        vm.startPrank(EOA_ADDRESS);
        BatchCallAndSponsor(EOA_ADDRESS).execute(calls);
        vm.stopPrank();

        console.log("Initial delegation successful");
        console.log("Sponsor's token balance after first delegation:", token.balanceOf(SPONSOR_ADDRESS));
    }

    function testReDelegation() internal {
        console.log("Attempting to re-delegate to V2 implementation...");

        vm.signAndAttachDelegation(address(implementation2), EOA_PK);
        vm.startPrank(EOA_ADDRESS);
        
        BatchCallAndSponsor.Call[] memory calls = new BatchCallAndSponsor.Call[](2);
        
        calls[0] = BatchCallAndSponsor.Call({
            to: address(token),
            value: 0,
            data: abi.encodeCall(ERC20.transfer, (SPONSOR_ADDRESS, 25e18))
        });
        
        calls[1] = BatchCallAndSponsor.Call({
            to: EOA_ADDRESS,
            value: 0,
            data: abi.encodeCall(BatchCallAndSponsorV2.performV2Action, ("Testing V2 functionality"))
        });

        try BatchCallAndSponsor(EOA_ADDRESS).execute(calls) {
            console.log("Re-delegation successful!");
            console.log("Executed V2-specific functionality");
        } catch Error(string memory reason) {
            console.log("Re-delegation failed with reason:", reason);
        } catch {
            console.log("Re-delegation failed with unknown error");
        }
        
        vm.stopPrank();

        console.log("Final sponsor token balance:", token.balanceOf(SPONSOR_ADDRESS));
    }

    function testSponsoredReDelegation() internal {
        console.log("\n--- Testing Sponsored Re-Delegation ---");
        
        Vm.SignedDelegation memory signedDelegation = vm.signDelegation(address(implementation2), EOA_PK);
        
        vm.startBroadcast(SPONSOR_PK);
        vm.attachDelegation(signedDelegation);

        BatchCallAndSponsor.Call[] memory calls = new BatchCallAndSponsor.Call[](1);
        address recipient = makeAddr("recipient2");
        calls[0] = BatchCallAndSponsor.Call({to: recipient, value: 0.0001 ether, data: ""});

        bytes memory encodedCalls = abi.encodePacked(calls[0].to, calls[0].value, calls[0].data);
        
        uint256 currentNonce = BatchCallAndSponsor(EOA_ADDRESS).nonce();
        bytes32 digest = keccak256(abi.encodePacked(currentNonce, encodedCalls));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(EOA_PK, MessageHashUtils.toEthSignedMessageHash(digest));
        bytes memory signature = abi.encodePacked(r, s, v);

        try BatchCallAndSponsor(EOA_ADDRESS).execute(calls, signature) {
            console.log("Sponsored re-delegation transaction successful");
        } catch Error(string memory reason) {
            console.log("Sponsored re-delegation failed:", reason);
        }

        vm.stopBroadcast();
        
        console.log("Recipient balance after sponsored re-delegation:", recipient.balance);
    }
}