// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "../contracts/SwapToken.sol";

contract TitaniumFactory {
    mapping(address => bool) public isPair;
    mapping(address => mapping(address => address)) public getPair;
    event pairCreated(address token0, address token1, address pair);
    address t0;
    address t1;

    function createPair(address _token0, address _token1)
        public
        returns (address _pair)
    {
        require(_token0 != _token1, "Identical Address");
        (address token0, address token1) = _token0 < _token1
            ? (_token0, _token1)
            : (_token1, _token0);
        require(token0 != address(0), "Zero Address");
        require(getPair[token0][token1] == address(0), "Pair Exists");
        (t0, t1) = (token0, token1);
        bytes32 data = keccak256(abi.encodePacked(token0, token1));
        _pair = address(new SwapToken{salt: data}());
        getPair[token0][token1] = _pair;
        getPair[token1][token0] = _pair;
        isPair[_pair] = true;
        emit pairCreated(token0, token1, _pair);
    }

    function getTokenAddress()
        public
        view
        returns (address _token0, address _token1)
    {
        return (t0, t1);
    }
}
