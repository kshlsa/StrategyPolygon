pragma solidity 0.6.12;

interface ICurvePool {
    function remove_liquidity(
        uint256 _amount,
        uint256[3] calldata _min_amounts,
        bool _use_underlying
    ) external returns (uint256[3] memory);

    function calc_token_amount(uint256[3] calldata _amounts, bool is_deposit)
        external
        view
        returns (uint256);

    function add_liquidity(
        uint256[3] calldata _amounts,
        uint256 _min_mint_amount,
        bool _use_underlying
    ) external returns (uint256);

    function underlying_coins(uint256 arg0) external returns (address);

    function lp_token() external view returns (address);

    function calc_withdraw_one_coin(uint256 _token_amount , int128 i) external view returns (uint256);

    function remove_liquidity_one_coin(uint256 _token_amount, int128 i, uint256 _min_amount, bool _use_underlying) external returns (uint256);

    function get_virtual_price() external view returns (uint256);
}