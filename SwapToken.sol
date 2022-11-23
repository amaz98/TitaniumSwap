// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../contracts/TitaniumFactory.sol";

contract SwapToken {
    uint256 public reserve0;
    uint256 public reserve1;
    uint256 public totalSupply;
    address public token0;
    address public token1;
    mapping(address => uint256) public balanceLP;
    uint256 internal constant MIN_LIQUIDITY = 10**3;
    address factory;

    constructor() {
        factory = msg.sender;
        (token0, token1) = TitaniumFactory(factory).getTokenAddress();
    }

    function sqrt(uint x) internal pure returns (uint y) {
        uint z = (x + 1) / 2;
        y = x;
        while (z < y) {
            y = z;
            z = (x / z + z) / 2;
        }
    }

    function min(uint a, uint b) internal pure returns (uint) {
        return a < b ? a : b;
    }

    //update reserves
    function swapTokens(
        uint256 _amount0In,
        uint256 _amount1In,
        address _to
    ) external {
        require(_amount0In > 0 || _amount1In > 0, "Insufficient Balance");
        require(_to != token0 && _to != token1, "Invalid To address");
        if (_amount0In > 0) {
            _safeTransfer(_to, token0, _amount0In);
        }
        if (_amount1In > 0) {
            _safeTransfer(_to, token1, _amount1In);
        }
        uint256 balnace0 = IERC20(token0).balanceOf(address(this));
        uint256 balance1 = IERC20(token1).balanceOf(address(this));
        _update(balnace0, balance1);
    }

    function mint(address _to) external returns (uint256 liquidity) {
        (uint256 _reserve0, uint256 _reserve1) = (reserve0, reserve1);
        uint256 balance0 = IERC20(token0).balanceOf(address(this));
        uint256 balance1 = IERC20(token1).balanceOf(address(this));
        uint256 amount0 = balance0 - reserve0;
        uint256 amount1 = balance1 - reserve1;
        uint256 _totalSupply = totalSupply;
        require(
            balance0 > reserve0 || balance1 > reserve1,
            "No Liquidity Was Deposited"
        );

        if (_totalSupply == 0) {
            liquidity = sqrt(amount0 * amount1);
            liquidity = liquidity - MIN_LIQUIDITY;
            _mint(MIN_LIQUIDITY, address(0));
        } else {
            liquidity = min(
                (amount0 * _totalSupply) / _reserve0,
                (amount1 * _totalSupply) / _reserve1
            );
        }
        _mint(liquidity, _to);
        _update(balance0, balance1);
    }

    function _mint(uint256 _liquidity, address _to) internal {
        balanceLP[_to] = _liquidity;
        totalSupply = totalSupply + _liquidity;
    }

    function burn(address _to)
        external
        returns (uint256 _amountA, uint256 _amountB)
    {
        uint256 liquidity = balanceLP[address(this)];
        // burn LP tokens from this contract
        balanceLP[address(this)] -= liquidity;
        uint256 balance0 = IERC20(token0).balanceOf(address(this));
        uint256 balance1 = IERC20(token1).balanceOf(address(this));
        _amountA = (liquidity * balance0) / totalSupply;
        _amountB = (liquidity * balance1) / totalSupply;
        require(_amountA > 0 && _amountB > 0, "Insufficient Liquidity Burned");
        _safeTransfer(_to, token0, _amountA);
        _safeTransfer(_to, token1, _amountB);
        balance0 = IERC20(token0).balanceOf(address(this));
        balance1 = IERC20(token1).balanceOf(address(this));
        _update(balance0, balance1);
    }

    function calcK(uint256 _x, uint256 _y) internal pure returns (uint256) {
        return _x * _y;
    }

    function amountOut(address _tokenIn, uint256 _amountIn)
        external
        view
        returns (uint256)
    {
        return _amountOut(_tokenIn, _amountIn, reserve0, reserve1);
    }

    function _amountOut(
        address _tokenIn,
        uint256 _amountIn,
        uint256 _reserve0,
        uint256 _reserve1
    ) internal view returns (uint256) {
        uint256 reserveA = _tokenIn == token0 ? (_reserve0) : (_reserve1);
        return calcK(_reserve0, _reserve1) / (reserveA + _amountIn);
    }

    // updates reserves
    function _update(uint256 _balance0, uint256 _balance1) internal {
        reserve0 = _balance0;
        reserve1 = _balance1;
    }

    function _safeTransfer(
        address _to,
        address _token,
        uint256 _amount
    ) internal {
        require(_token.code.length > 0);
        (bool success, bytes memory data) = _token.call(
            abi.encodeWithSelector(IERC20.transfer.selector, _to, _amount)
        );
        require(success && (data.length == 0 || abi.decode(data, (bool))));
    }

    function _safeTransferETH(address _to, uint256 _amount) internal {
        (bool success, ) = _to.call{value: _amount}(new bytes(0));
        require(success, "ETH Transfer Failed");
    }

    function transferFrom(
        address _sender,
        address _receiver,
        uint256 _amount
    ) public {
        balanceLP[_sender] -= _amount;
        balanceLP[_receiver] += _amount;
    }

    function _getReserves() public view returns (uint256, uint256) {
        return (reserve0, reserve1);
    }
}
