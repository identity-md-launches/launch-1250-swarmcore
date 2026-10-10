// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {SwarmCore} from "../src/SwarmCore.sol";

/// @dev Local fixture only: illustrates the immediate deployer's receipt and distribution of supply.
contract TokenFactoryFixture {
    function deploy(bytes32 salt) external returns (SwarmCore) {
        return new SwarmCore{salt: salt}();
    }

    function move(SwarmCore token, address to, uint256 amount) external returns (bool) {
        return token.transfer(to, amount);
    }
}

contract SwarmCoreLaunchTest is Test {
    uint256 private constant SUPPLY = 1_000_000_000 * 1e18;

    TokenFactoryFixture private factory;
    SwarmCore private token;
    address private distributor;
    address private poolCustodian;
    address private remainderRecipient;
    address private claimant;
    address private trader;

    function setUp() public {
        factory = new TokenFactoryFixture();
        token = factory.deploy(bytes32(uint256(1)));
        // All addresses below are isolated test actors, not deployment configuration.
        distributor = makeAddr("distributor");
        poolCustodian = makeAddr("pool custodian");
        remainderRecipient = makeAddr("remainder recipient");
        claimant = makeAddr("claimant");
        trader = makeAddr("trader");
    }

    function test_FactoryReceivesEntireSupply() public view {
        assertEq(token.balanceOf(address(factory)), SUPPLY);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_Create2UsesArgumentFreeCreationCode(bytes32 salt) public {
        // The initial fixture deployment already uses salt 1.
        vm.assume(salt != bytes32(uint256(1)));
        address expected = address(
            uint160(
                uint256(
                    keccak256(
                        abi.encodePacked(bytes1(0xff), address(factory), salt, keccak256(type(SwarmCore).creationCode))
                    )
                )
            )
        );
        vm.prank(trader, claimant);
        SwarmCore deployed = factory.deploy(salt);
        assertEq(address(deployed), expected);
        assertEq(deployed.balanceOf(address(factory)), SUPPLY);
        assertEq(deployed.balanceOf(trader), 0);
        assertEq(deployed.balanceOf(claimant), 0);
        assertEq(deployed.totalSupply(), SUPPLY);
    }

    function test_LaunchDistributionAndClaimsArriveWhole() public {
        uint256 swarmShare = SUPPLY * 1000 / 10_000;
        uint256 poolShare = SUPPLY * 8800 / 10_000;
        uint256 remainder = SUPPLY * 200 / 10_000;
        assertTrue(factory.move(token, distributor, swarmShare));
        assertTrue(factory.move(token, poolCustodian, poolShare));
        assertTrue(factory.move(token, remainderRecipient, remainder));
        assertEq(token.balanceOf(address(factory)), 0);
        assertEq(token.balanceOf(distributor), swarmShare);
        assertEq(token.balanceOf(poolCustodian), poolShare);
        assertEq(token.balanceOf(remainderRecipient), remainder);

        vm.prank(distributor);
        assertTrue(token.transfer(claimant, swarmShare));
        assertEq(token.balanceOf(distributor), 0);
        assertEq(token.balanceOf(claimant), swarmShare);
        assertEq(token.totalSupply(), SUPPLY);
    }

    /// @dev Tests exact token movement in both directions, not Uniswap pricing or settlement.
    function test_PoolCustodianAndOrdinaryTraderCanTransferBothWays() public {
        uint256 poolShare = SUPPLY * 8800 / 10_000;
        assertTrue(factory.move(token, poolCustodian, poolShare));
        vm.prank(poolCustodian);
        assertTrue(token.transfer(trader, 123 ether));
        assertEq(token.balanceOf(trader), 123 ether);
        vm.prank(trader);
        assertTrue(token.transfer(poolCustodian, 123 ether));
        assertEq(token.balanceOf(trader), 0);
        assertEq(token.balanceOf(poolCustodian), poolShare);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_DeployerAndStrangerHaveNoMintBurnOrAdministrativeEntrypoints() public {
        assertTrue(factory.move(token, claimant, 100 ether));
        bytes[] memory attempts = new bytes[](19);
        attempts[0] = abi.encodeWithSignature("mint(address,uint256)", trader, SUPPLY);
        attempts[1] = abi.encodeWithSignature("mint(uint256)", SUPPLY);
        attempts[2] = abi.encodeWithSignature("mint()");
        attempts[3] = abi.encodeWithSignature("issue(uint256)", SUPPLY);
        attempts[4] = abi.encodeWithSignature("burn(uint256)", 1);
        attempts[5] = abi.encodeWithSignature("burnFrom(address,uint256)", claimant, 1);
        attempts[6] = abi.encodeWithSignature("pause()");
        attempts[7] = abi.encodeWithSignature("unpause()");
        attempts[8] = abi.encodeWithSignature("blacklist(address)", claimant);
        attempts[9] = abi.encodeWithSignature("freeze(address)", claimant);
        attempts[10] = abi.encodeWithSignature("seize(address)", claimant);
        attempts[11] = abi.encodeWithSignature("setOwner(address)", trader);
        attempts[12] = abi.encodeWithSignature("transferOwnership(address)", trader);
        attempts[13] = abi.encodeWithSignature("upgradeTo(address)", trader);
        attempts[14] = abi.encodeWithSignature("initialize(address)", trader);
        attempts[15] = abi.encodeWithSignature("setMinter(address)", trader);
        attempts[16] = abi.encodeWithSignature("setTransfersEnabled(bool)", false);
        attempts[17] = abi.encodeWithSignature("setBlacklist(address,bool)", claimant, true);
        attempts[18] = abi.encodeWithSignature("lock(address)", claimant);

        for (uint256 i; i < attempts.length; ++i) {
            vm.prank(address(factory));
            (bool privilegedSuccess,) = address(token).call(attempts[i]);
            assertFalse(privilegedSuccess, "unexpected deployer privilege");
            vm.prank(trader);
            (bool strangerSuccess,) = address(token).call(attempts[i]);
            assertFalse(strangerSuccess, "unexpected public entrypoint");
            assertEq(token.totalSupply(), SUPPLY);
            assertEq(token.balanceOf(claimant), 100 ether);
            assertEq(token.balanceOf(address(factory)), SUPPLY - 100 ether);
            assertEq(token.balanceOf(trader), 0);
        }

        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(factory), 0, 1)
        );
        vm.prank(address(factory));
        token.transferFrom(claimant, address(factory), 1);

        vm.prank(claimant);
        assertTrue(token.transfer(trader, 100 ether));
        assertEq(token.balanceOf(claimant), 0);
        assertEq(token.balanceOf(trader), 100 ether);
    }

    function test_RuntimeIsSmallAndHasNoExternalCallOrDestructionOpcodes() public view {
        bytes memory runtime = address(token).code;
        assertGt(runtime.length, 0);
        assertLe(runtime.length, 24_576);
        for (uint256 i; i < runtime.length; ++i) {
            uint8 opcode = uint8(runtime[i]);
            if (opcode >= 0x60 && opcode <= 0x7f) {
                i += opcode - 0x5f;
                continue;
            }
            assertTrue(opcode != 0xf1, "CALL");
            assertTrue(opcode != 0xf2, "CALLCODE");
            assertTrue(opcode != 0xf4, "DELEGATECALL");
            assertTrue(opcode != 0xfa, "STATICCALL");
            assertTrue(opcode != 0xff, "SELFDESTRUCT");
        }
    }
}
