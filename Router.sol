// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./TitaniumFactory.sol";
import "./SwapToken.sol";

interface IWETH {
    function deposit() external payable;

    function transfer(address to, uint value) external returns (bool);

    function withdraw(uint) external;
}

contract Router {
    address public immutable factory;
    IWETH public immutable WETH;
    event liquidityAdded(uint256, uint256, uint256);
    event liquidityRemoved(uint256, uint256);

    constructor(address _factory, address _WETH) {
        factory = _factory;
        WETH = IWETH(_WETH);
    }

    modifier OnTime(uint256 deadline) {
        require(deadline >= block.timestamp, "EXPIRED");
        _;
    }

    function pairFor(address _token0, address _token1)
        public
        view
        returns (address _pair)
    {
        (address token0, address token1) = sortTokens(_token0, _token1);
        _pair = address(
            uint160(
                uint256(
                    keccak256(
                        abi.encodePacked(
                            hex"ff",
                            factory,
                            keccak256(abi.encodePacked(token0, token1)),
                            keccak256(type(SwapToken).creationCode)
                        )
                    )
                )
            )
        );
    }

    function sortTokens(address _token0, address _token1)
        internal
        pure
        returns (address token0, address token1)
    {
        (token0, token1) = _token0 < _token1
            ? (_token0, _token1)
            : (_token1, _token0);
    }

    function pairExists(address _token0, address _token1)
        internal
        view
        returns (bool)
    {
        return TitaniumFactory(factory).isPair(pairFor(_token0, _token1));
    }

    function addLiquidity(
        address _token0,
        address _token1,
        uint256 _token0Amount,
        uint256 _token1Amount,
        uint256 _token0Min,
        uint256 _token1Min,
        address _to
    )
        external
        returns (
            uint256 _tokenAAmount,
            uint256 _tokenBAmount,
            uint256 _liquidity
        )
    {
        require(pairExists(_token0, _token1), "Pair Does Not Exist");
        address pair = pairFor(_token0, _token1);
        address msgSender = msg.sender;
        (_tokenAAmount, _tokenBAmount) = _addLiquidity(
            _token0,
            _token1,
            _token0Amount,
            _token1Amount,
            _token0Min,
            _token1Min
        );
        _safeTransferFrom(msgSender, pair, _token0, _tokenAAmount);
        _safeTransferFrom(msgSender, pair, _token1, _tokenBAmount);
        _liquidity = SwapToken(pair).mint(_to);
        emit liquidityAdded(_tokenAAmount, _tokenBAmount, _liquidity);
    }

    function _addLiquidity(
        address _token0,
        address _token1,
        uint256 _token0Amount,
        uint256 _token1Amount,
        uint256 _token0Min,
        uint256 _token1Min
    ) public view returns (uint256 _amountA, uint256 _amountB) {
        require(_token0Amount >= _token0Min);
        require(_token1Amount >= _token1Min);
        address pair = pairFor(_token0, _token1);
        require(pair != address(0), "Pair does not exist");
        (uint256 reserveA, uint256 reserveB) = SwapToken(pair)._getReserves();
        if (reserveA == 0 && reserveB == 0) {
            (_amountA, _amountB) = (_token0Amount, _token1Amount);
        } else {
            uint256 amountBOptimal = quoteLiquidity(
                _token0Amount,
                reserveA,
                reserveB
            );
            if (amountBOptimal <= _token0Amount) {
                require(amountBOptimal >= _token1Min, "Insufficient Liquidity");
                (_amountA, _amountB) = (_token0Amount, amountBOptimal);
            } else {
                uint256 amountAOptimal = quoteLiquidity(
                    _token1Amount,
                    reserveB,
                    reserveA
                );
                require(amountAOptimal <= _token0Amount);
                require(amountAOptimal >= _token0Min, "Insufficient Liquidity");
                (_amountA, _amountB) = (amountAOptimal, _token1Amount);
            }
        }
    }

    function quoteLiquidity(
        uint256 _amountA,
        uint256 _reserveA,
        uint256 _reserveB
    ) internal pure returns (uint256 _amountB) {
        _amountB = (_amountA * _reserveB) / _reserveA;
    }

    function addETHLiquidity(
        address _token,
        uint256 _tokenIn,
        uint256 _tokenInMin,
        uint256 _amountETHMin,
        address _to
    )
        external
        payable
        returns (
            uint256 _amountToken,
            uint256 _amountETH,
            uint256 _liquidity
        )
    {
        uint256 amountETHIn = msg.value;
        address msgSender = msg.sender;
        address weth = address(WETH);
        require(amountETHIn >= _amountETHMin, "Not Enough ETH Sent");
        (_amountToken, _amountETH) = _addLiquidity(
            _token,
            weth,
            _tokenIn,
            amountETHIn,
            _tokenInMin,
            _amountETHMin
        );
        address pair = pairFor(_token, weth);
        _safeTransferFrom(msgSender, pair, _token, _amountToken);
        WETH.deposit{value: _amountETH}();
        assert(WETH.transfer(pair, _amountETH));
        _liquidity = SwapToken(pair).mint(_to);
        if (msg.value > _amountETH)
            _safeTransferETH(msg.sender, msg.value - _amountETH);
        emit liquidityAdded(_amountToken, _amountETH, _liquidity);
    }

    function removeLiquidity(
        address _tokenA,
        address _tokenB,
        uint256 _liquidity,
        uint256 _amountAMin,
        uint256 _amountBMin,
        address _to
    ) public returns (uint256 _amountA, uint256 _amountB) {
        address pair = pairFor(_tokenA, _tokenB);
        SwapToken(pair).transferFrom(msg.sender, pair, _liquidity);
        (_amountA, _amountB) = SwapToken(pair).burn(_to);
        // sort tokens
        (address token0, ) = _tokenA < _tokenB
            ? (_tokenA, _tokenB)
            : (_tokenB, _tokenA);
        (_amountA, _amountB) = _tokenA == token0
            ? (_amountA, _amountB)
            : (_amountB, _amountA);
        require(_amountA >= _amountAMin, "Insufficient A Amount");
        require(_amountB >= _amountBMin, "Insufficient B Amount");
        emit liquidityRemoved(_amountA, _amountB);
    }

    function removeETHLiquidity(
        address _tokenOut,
        uint256 _tokenOutMin,
        uint256 _ETHOutMin,
        uint256 _liquidity,
        address _to
    ) external returns (uint256 _amountTokenOut, uint256 _amountETHOut) {
        (_amountTokenOut, _amountETHOut) = removeLiquidity(
            _tokenOut,
            address(WETH),
            _liquidity,
            _tokenOutMin,
            _ETHOutMin,
            _to
        );
        _safeTransfer(_to, _tokenOut, _amountTokenOut);
        IWETH(WETH).withdraw(_amountETHOut);
        _safeTransferETH(_to, _amountETHOut);
    }

    function swapExactTokensForTokens(
        uint256 _amountIn,
        uint256 _amountOutMin,
        address[] calldata _path,
        address _to
    ) external {
        uint256[] memory amounts = getAmountsOut(_amountIn, _path);
        require(
            amounts[_path.length - 1] >= _amountOutMin,
            "Insufficient Output Amount"
        );
        address initialToken = _path[0];
        _safeTransferFrom(
            msg.sender,
            pairFor(initialToken, _path[1]),
            initialToken,
            _amountIn
        );
        _swap(_path, amounts, _to);
    }

    function swapExactTokensForTokensOnePath(
        uint256 _amountIn,
        uint256 _amountOutMin,
        address[] calldata _path,
        address _to
    ) external {
        require(_path.length == 2, "Too Many Paths");
        address tokenIn = _path[0];
        address tokenOut = _path[1];
        address pair = pairFor(tokenIn, tokenOut);
        uint256 amountOut = SwapToken(pair).amountOut(tokenIn, _amountIn);
        require(amountOut >= _amountOutMin, "Insufficient Liquidity");
        _safeTransferFrom(msg.sender, pair, tokenIn, _amountIn);
        (address token0, ) = sortTokens(tokenIn, tokenOut);
        (uint256 amount0Out, uint256 amount1Out) = token0 == tokenIn
            ? (uint256(0), amountOut)
            : (amountOut, uint256(0));
        SwapToken(pair).swapTokens(amount0Out, amount1Out, _to);
    }

    function swapETHForExactTokens(
        uint256 _amountOutMin,
        address[] calldata _path,
        address _to,
        uint256 _deadline
    ) external payable OnTime(_deadline) {
        require(_path[0] == address(WETH));
        uint256 amountIn = msg.value;
        uint256[] memory amounts = getAmountsOut(amountIn, _path);
        require(
            amounts[amounts.length - 1] >= _amountOutMin,
            "Insufficient Liquidity"
        );
        IWETH(WETH).deposit{value: amountIn}();
        address pair = pairFor(address(WETH), _path[1]);
        assert(IWETH(WETH).transfer(pair, amountIn));
        _swap(_path, amounts, _to);
    }

    function swapExactTokensForETH(
        uint256 _amountIn,
        uint256 _amountOutMin,
        address[] memory _path,
        address _to,
        uint256 _deadline
    ) external OnTime(_deadline) {}

    function getAmountsOut(uint256 _amountIn, address[] calldata _path)
        internal
        view
        returns (uint256[] memory _amounts)
    {
        require(_path.length >= 2, "Invalid Path");
        _amounts = new uint256[](_path.length);
        _amounts[0] = _amountIn;
        for (uint256 i = 0; i < _path.length - 1; i++) {
            address tokenIn = _path[i];
            address pair = pairFor(tokenIn, _path[i + 1]);
            require(TitaniumFactory(factory).isPair(pair), "Not Valid Pair");
            _amounts[i + 1] = SwapToken(pair).amountOut(tokenIn, _amounts[i]);
        }
    }

    function _swap(
        address[] memory _path,
        uint256[] memory _amounts,
        address _to
    ) internal {
        for (uint256 i = 0; i < _path.length; i++) {
            uint256 amountOut = _amounts[i + 1];
            address pair = pairFor(_path[i], _path[i + 1]);
            (address token0, ) = sortTokens(_path[i], _path[i + 1]);
            (uint256 amount0Out, uint256 amount1Out) = _path[i] == token0
                ? (uint256(0), amountOut)
                : (amountOut, uint256(0));
            SwapToken(pair).swapTokens(amount0Out, amount1Out, _to);
        }
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

    function _safeTransferFrom(
        address _from,
        address _to,
        address _token,
        uint256 _amount
    ) internal {
        require(_token.code.length > 0);
        (bool success, bytes memory data) = _token.call(
            abi.encodeWithSelector(
                IERC20.transferFrom.selector,
                _from,
                _to,
                _amount
            )
        );
        require(success && (data.length == 0 || abi.decode(data, (bool))));
    }

    function _safeTransferETH(address to, uint value) internal {
        (bool success, ) = to.call{value: value}(new bytes(0));
        require(success, "ETH Transfer Failed");
    }
}
