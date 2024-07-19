// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {Test} from "forge-std/Test.sol";
import {DeployRaffle} from "script/DeployRaffle.s.sol";
import {Raffle} from "src/Raffle.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {Vm} from "forge-std/Vm.sol";
import {VRFCoordinatorV2_5Mock} from "@chainlink/contracts/src/v0.8/vrf/mocks/VRFCoordinatorV2_5Mock.sol";
import{CodeConstants} from "script/HelperConfig.s.sol";



contract RaffleTest is CodeConstants, Test {
     Raffle public raffle;
     HelperConfig public helperconfig;
        
        uint256 entranceFee;
        uint256 interval;
        address vrfCoordinator;
        bytes32 gasLane; 
        uint32 callbackGasLimit;
        uint256 subscriptionId;

        address public PLAYER = makeAddr("player");
        uint256 public constant STARTING_PLAYER_BALANCE = 10 ether;

        event RaffleEnter(address indexed player);
        event WinnerPicked(address indexed player);

    function setUp() external {
        DeployRaffle deployer = new DeployRaffle();
        (raffle, helperconfig) = deployer.deployContract();
        HelperConfig.NetworkConfig memory config = helperconfig.getConfig();
        entranceFee = config.entranceFee;
        interval = config.interval;
        vrfCoordinator = config.vrfCoordinator;
        gasLane = config.gasLane;
        subscriptionId = config.subscriptionId;
        callbackGasLimit = config.callbackGasLimit;
        vm.deal(PLAYER, STARTING_PLAYER_BALANCE);
    }

    function testRaffleInitializesInOpenState() public view {
        assert(raffle.getRaffleState() == Raffle.RaffleState.OPEN);
    }

    function testRaffleRevertsWhenYouDontPayEnough() public {
        // arange
        vm.prank(PLAYER);
        // act / asset
        vm.expectRevert(Raffle.Raffle__SendMoreToEnterRaffle.selector);
        raffle.enterRaffle();
    }

    function testRaffleRecordsPlayersWhenTheyEnter() public {
        // arange
        vm.prank(PLAYER);
        // act
        raffle.enterRaffle{value: entranceFee}();
        // asset
        address playerRecorded = raffle.getPlayer(0);
        assert(playerRecorded == PLAYER);
    }

    function testEnteringRaffleEmitsEvent() public {
        // arange
        vm.prank(PLAYER);
        // act
        vm.expectEmit(true, false, false, false, address(raffle));
        emit RaffleEnter(PLAYER);
        // assert
        raffle.enterRaffle{value:entranceFee}();
    }

    function test_DontAllowPlayersToEnterWhileRaffleIsCalculating() public {
       // arange
       vm.prank(PLAYER);
       raffle.enterRaffle {value: entranceFee}();
       vm.warp(block.timestamp + interval +1);
       vm.roll(block.number + 1);
       raffle.performUpkeep("");
       // act / assert 
       vm.expectRevert(Raffle.Raffle__RaffleNotOpen.selector);
       vm.prank(PLAYER);
       raffle.enterRaffle{value: entranceFee}();
    }

    /*//////////////////////////////////////////////////////
                       CHECK UPKEEP
    /////////////////////////////////////////////////////*/
    function testCheckUpkeepReturnsFalseIfItHasNoBalance() public {
        // Arange
       vm.warp(block.timestamp + interval +1);
       vm.roll(block.number + 1);
       // Act
       (bool upkeepNeeded,) = raffle.checkUpkeep("");
       // Assert
       assert(!upkeepNeeded);
    }
    
    function testCheckUpkeepReturnsFalseIfRaffleIsntOpen() public {
       // arange
       vm.prank(PLAYER);
       raffle.enterRaffle {value: entranceFee}();
       vm.warp(block.timestamp + interval +1);
       vm.roll(block.number + 1);
       raffle.performUpkeep(""); 

       // act
       (bool upkeepNeeded,) = raffle.checkUpkeep("");

       // assert 
      assert(!upkeepNeeded);

    }
    // challange
    // testCheckUpkeepReturnsFalseIfEnoughTimeHasPassed
    // testCheckUpkeepReturnsTrueWhenParameterAreGood

    /*//////////////////////////////////////////////////////
                       CHECK UPKEEP
    /////////////////////////////////////////////////////*/

    function testCheckUpkeepReturnsFalseIfEnoughTimeHasPassed() public {
        // Arange
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();

        // Act
        (bool upkeepNeeded, ) = raffle.checkUpkeep("");
        
        // Assert
        assert(!upkeepNeeded);
    }
    function testCheckUpkeepReturnsTrueWhenParameterAreGood() public {
              // Arange
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);
        vm.deal(address(raffle), 1 ether);
        // Act
        (bool upkeepNeeded, ) = raffle.checkUpkeep("");
        // Assert
        assert(upkeepNeeded);  
    }
    function testPerformUpkeepCanOnlyRunIfCheckUpkeepIsTrue() public {
                    // Arange
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);  
        //Act / Assert
        raffle.performUpkeep("");
    }
    function testPerformUpkeepRevertsIfCheckUpkeepIsFalse() public{
        // Arange
        uint256 currentBalance = 0;
        uint256 numPlayers = 0;
        Raffle.RaffleState rsState = raffle.getRaffleState();

        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
        currentBalance = currentBalance + entranceFee;
        numPlayers = 1;

        // Act /Assert
        vm.expectRevert(
            abi.encodeWithSelector(Raffle.Raffle__UpkeepNotNeeded.selector, currentBalance, numPlayers, rsState)

        );
        raffle.performUpkeep("");
    }  

    modifier RaffleEntered() {
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1); 
        _;
    }

    // what is we need to get data from enitted events in our tests?
    function testPerformUpkeepUpdatesRaffleStateAndEmitsRequestId() public RaffleEntered {

        // Act
        vm.recordLogs();
        raffle.performUpkeep("");
        Vm.Log[] memory entries = vm.getRecordedLogs();
        bytes32 requestId = entries[1].topics[1];

        // Assert
        Raffle.RaffleState raffleState = raffle.getRaffleState();
        assert(uint256(requestId) > 0);
        assert(uint256(raffleState) == 1);
    }

    modifier skipFork() {
        if (block.chainid != LOCAL_CHAIN_ID) {
            return;
        }
        _;
    }

    function testFulfillrandomWordsCanOnlyBeCalledAfterPerformUpkeep(uint256 randomRequestId) public RaffleEntered {
        // Arrange / Act / Assert
        vm.expectRevert(VRFCoordinatorV2_5Mock.InvalidRequest.selector);
        VRFCoordinatorV2_5Mock(vrfCoordinator).fulfillRandomWords(randomRequestId, address(raffle));

    }
    function testFulfillrandomwordsPciksWinnerResetsAndSendsMoney() public RaffleEntered {
        // Arange
        
        uint256 additionalEntrants = 3; // 4 real
        uint256 startingIndex = 1;
        address expectedWinner = address(1);

        for(uint256 i = startingIndex; i <  startingIndex + additionalEntrants; i++) {
           address newplayer = address(uint160(i));
           hoax(newplayer, 1 ether);
           raffle.enterRaffle{value: entranceFee}(); 
        }
        uint256 startingTimeStamp = raffle.getLasTimeStamp();
        uint256 winnerStartingBalance = expectedWinner.balance;
        // Act
                vm.recordLogs();
        raffle.performUpkeep("");
        Vm.Log[] memory entries = vm.getRecordedLogs();
        bytes32 requestId = entries[1].topics[1];
        VRFCoordinatorV2_5Mock(vrfCoordinator).fulfillRandomWords (uint256(requestId), address(raffle));

        // Assert
        address recentWinner = raffle.getRecentWinner();
        Raffle.RaffleState raffleState = raffle.getRaffleState();
        uint256 winnerBalance = recentWinner.balance;
        uint256 endingTimeStamp  = raffle.getLasTimeStamp();
        uint256 prize = entranceFee * (additionalEntrants + 1);

        assert(recentWinner == expectedWinner);
        assert(uint256(raffleState) == 0);
        assert(winnerBalance == winnerStartingBalance + prize);
        assert(endingTimeStamp > startingTimeStamp);

    }
     


}