// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import "./TestUtils.sol";
import "../src/lib/Math.sol";
import "./ERC20Mintable.sol";
import "../src/UniswapV3Manager.sol";
import {Test, console2 as console} from "forge-std/Test.sol";

contract UniswapV3PoolTest is Test, TestUtils {
    ERC20Mintable token0;
    ERC20Mintable token1;
    UniswapV3Pool pool;
    UniswapV3Manager manager;

    struct TestCaseParams {
        int24 currentTick;
        int24 lowerTick;
        int24 upperTick;
        uint128 liquidity;
        uint160 currentSqrtP;
        bool mintLiqudity;
    }

    bool transferInMintCallback = true;
    bool transferInSwapCallback = true;

    function setUp() public {
        token0 = new ERC20Mintable("Ether", "ETH", 18);
        token1 = new ERC20Mintable("USDC", "USDC", 18);
    }

    function testMintSuccess() public {
        TestCaseParams memory params = TestCaseParams({
            currentTick: 85176,
            lowerTick: 84222,
            upperTick: 86129,
            liquidity: 1517882343751509868544,
            currentSqrtP: 5602277097478614198912276234240,
            mintLiqudity: true
        });

        (
            uint256 expectedAmount0,
            uint256 expectedAmount1,
            uint160 sqrtPriceX96,
            int24 tick
        ) = setupTestCase(params);

        uint256 poolBalance0 = token0.balanceOf(address(pool));
        uint256 poolBalance1 = token1.balanceOf(address(pool));

        assertEq(
            poolBalance0,
            expectedAmount0,
            "incorrect token0 deposited amount"
        );

        assertEq(
            poolBalance1,
            expectedAmount1,
            "incorrect token1 deposited amount"
        );

        bytes32 positionKey = keccak256(
            abi.encodePacked(address(this), params.lowerTick, params.upperTick)
        );

        uint128 posLiquidity = pool.positions(positionKey);
        assertEq(posLiquidity, params.liquidity);

        (bool tickInitialized, uint128 tickLiquidity) = pool.ticks(
            params.lowerTick
        );

        assertTrue(tickInitialized);
        assertEq(tickLiquidity, params.liquidity);

        (tickInitialized, tickLiquidity) = pool.ticks(params.upperTick);

        assertTrue(tickInitialized);
        assertEq(tickLiquidity, params.liquidity);

        assertEq(sqrtPriceX96, params.currentSqrtP, "invalid current sqrtP");

        assertEq(tick, params.currentTick, "invalid current tick");

        assertEq(
            pool.liquidity(),
            params.liquidity,
            "invalid current liquidity"
        );
    }

    function testSwapBuyEth() public {
        TestCaseParams memory params = TestCaseParams({
            currentTick: 85176,
            lowerTick: 84222,
            upperTick: 86129,
            liquidity: 1517882343751509868544,
            currentSqrtP: 5602277097478614198912276234240,
            mintLiqudity: true
        });

        UniswapV3Pool.CallbackData memory extra = UniswapV3Pool.CallbackData({
            token0: address(token0),
            token1: address(token1),
            payer: address(this)
        });

        setupTestCase(params);

        token1.mint(address(this), 42 ether);
        int userBalance0Before = int(token0.balanceOf(address(this)));
        int userBalance1Before = int256(token1.balanceOf(address(this)));

        uint256 poolBalance0 = token0.balanceOf(address(pool));
        uint256 poolBalance1 = token1.balanceOf(address(pool));

        uint256 swapAmount = 42 ether;
        token1.approve(address(manager), 42 ether);

        (int256 amount0Delta, int256 amount1Delta) = manager.swap(
            address(pool),
            false,
            swapAmount,
            abi.encode(extra)
        );

        assertEq(
            token0.balanceOf(address(this)),
            uint256(userBalance0Before - amount0Delta),
            "invalid user ETH balance"
        );

        assertEq(
            token0.balanceOf(address(pool)),
            uint256(int256(poolBalance0) + amount0Delta),
            "invalid pool ETH balance"
        );

        assertEq(
            token1.balanceOf(address(this)),
            uint256(userBalance1Before - amount1Delta),
            "invalid user USDC balance"
        );

        assertEq(
            token1.balanceOf(address(pool)),
            uint256(int256(poolBalance1) + amount1Delta),
            "invalid pool USDC balance"
        );

        (uint160 sqrtPriceX96, int24 tick) = pool.slot0();

        assertEq(
            sqrtPriceX96,
            5604469350942327889444743441197,
            "invalid current sqrtP"
        );

        assertEq(tick, 85184, "invalid current tick");

        assertEq(
            pool.liquidity(),
            params.liquidity,
            "invalid current liquidity"
        );
    }

    function setupTestCase(
        TestCaseParams memory params
    )
        internal
        returns (
            uint256 wethBalance,
            uint256 usdcBalance,
            uint160 sqrtPriceX96,
            int24 tick
        )
    {
        pool = new UniswapV3Pool(
            address(token0),
            address(token1),
            params.currentSqrtP,
            params.currentTick
        );

        manager = new UniswapV3Manager();

        UniswapV3Pool.CallbackData memory extra = UniswapV3Pool.CallbackData({
            token0: address(token0),
            token1: address(token1),
            payer: address(this)
        });

        if (params.mintLiqudity) {
            (sqrtPriceX96, tick) = pool.slot0();

            wethBalance = Math.calcAmount0Delta(
                TickMath.getSqrtRatioAtTick(tick),
                TickMath.getSqrtRatioAtTick(params.upperTick),
                params.liquidity
            );

            usdcBalance = Math.calcAmount1Delta(
                TickMath.getSqrtRatioAtTick(tick),
                TickMath.getSqrtRatioAtTick(params.lowerTick),
                params.liquidity
            );

            token0.mint(address(this), wethBalance);
            token1.mint(address(this), usdcBalance);

            token0.approve(address(manager), wethBalance);
            token1.approve(address(manager), usdcBalance);

            manager.mint(
                address(pool),
                params.lowerTick,
                params.upperTick,
                params.liquidity,
                abi.encode(extra)
            );
        }
    }
}
