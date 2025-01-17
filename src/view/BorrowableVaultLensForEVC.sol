// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.0;

import "solmate/utils/FixedPointMathLib.sol";
import "evc/interfaces/IEthereumVaultConnector.sol";
import "../vaults/VaultRegularBorrowable.sol";
import "./Types.sol";

contract BorrowableVaultLensForEVC {
    uint256 internal constant SECONDS_PER_YEAR = 365.2425 * 86400;
    IEVC public immutable evc;

    constructor(IEVC _evc) {
        evc = _evc;
    }

    function getEVCUserInfo(address account) external view returns (EVCUserInfo memory) {
        address owner;
        try evc.getAccountOwner(account) returns (address _owner) {
            owner = _owner;
        } catch {
            owner = account;
        }

        return EVCUserInfo({
            account: account,
            addressPrefix: evc.getAddressPrefix(account),
            owner: owner,
            enabledControllers: evc.getControllers(account),
            enabledCollaterals: evc.getCollaterals(account)
        });
    }

    function getVaultUserInfo(address account, address vault) external view returns (ERC4626UserInfo memory) {
        uint256 shares = ERC4626(vault).balanceOf(account);

        return ERC4626UserInfo({
            account: account,
            vault: vault,
            shares: shares,
            assets: ERC4626(vault).convertToAssets(shares),
            borrowed: VaultRegularBorrowable(vault).debtOf(account),
            isController: evc.isControllerEnabled(account, vault),
            isCollateral: evc.isCollateralEnabled(account, vault)
        });
    }

    function getVaultInfo(address vault) external view returns (ERC4626VaultInfo memory) {
        address asset = address(ERC4626(vault).asset());
        uint256 interestRateSPY = VaultRegularBorrowable(vault).getInterestRate();

        return ERC4626VaultInfo({
            vault: vault,
            vaultName: getStringOrBytes32(vault, ERC20(vault).name.selector),
            vaultSymbol: getStringOrBytes32(vault, ERC20(vault).symbol.selector),
            vaultDecimals: ERC20(vault).decimals(),
            asset: asset,
            assetName: getStringOrBytes32(asset, ERC20(asset).name.selector),
            assetSymbol: getStringOrBytes32(asset, ERC20(asset).symbol.selector),
            assetDecimals: ERC20(asset).decimals(),
            totalShares: ERC20(vault).totalSupply(),
            totalAssets: ERC4626(vault).totalAssets(),
            totalBorrowed: VaultRegularBorrowable(vault).totalBorrowed(),
            interestRateSPY: interestRateSPY,
            interestRateAPY: FixedPointMathLib.rpow(interestRateSPY + 1e27, SECONDS_PER_YEAR, 1e27) - 1e27,
            irm: address(VaultRegularBorrowable(vault).irm()),
            oracle: address(VaultRegularBorrowable(vault).oracle())
        });
    }

    /// @dev for tokens like MKR which return bytes32 on name() or symbol()
    function getStringOrBytes32(address contractAddress, bytes4 selector) private view returns (string memory) {
        (bool success, bytes memory result) = contractAddress.staticcall(abi.encodeWithSelector(selector));

        return success ? result.length == 32 ? string(abi.encodePacked(result)) : abi.decode(result, (string)) : "";
    }
}
