import 'package:auto_route/auto_route.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_fuelet_contracts/flutter_fuelet_contracts.dart';
import 'package:flutter_fuels/flutter_fuels.dart';
import 'package:flutter_svg/svg.dart';
import 'package:wallet/application/accounts/accounts_bloc.dart';
import 'package:wallet/application/balances/balances_bloc/balances_bloc.dart';
import 'package:wallet/domain/account/entities/account.dart';
import 'package:wallet/domain/balances/entities/balance.dart';
import 'package:wallet/domain/blockchain_network/blockchain_network.dart';
import 'package:wallet/gen/assets.gen.dart';
import 'package:wallet/presentation/core/routes/router.gr.dart';
import 'package:wallet/presentation/core/widgets/app_bar.dart';
import 'package:wallet/presentation/core/widgets/buttons/primary_button.dart';
import 'package:wallet/presentation/core/widgets/icon_button.dart';
import 'package:wallet/presentation/core/widgets/scaffold.dart';
import 'package:wallet/presentation/send_coin/widgets/coin_amount_input.dart';
import 'package:wallet/presentation/send_coin/widgets/coin_balance_widget.dart';

class SendCoinScreen extends StatefulWidget {
  final TokenBalance tokenBalance;
  final Account account;

  const SendCoinScreen({
    super.key,
    required this.tokenBalance,
    required this.account,
  });

  @override
  State<SendCoinScreen> createState() => _SendCoinScreenState();
}

class _SendCoinScreenState extends State<SendCoinScreen> {
  late final double _knownBalance;

  final _amountFocusNode = FocusNode();
  final _amountTextController = TextEditingController();
  final _dio = Dio();

  double get _amountValue {
    return double.tryParse(_amountTextController.text.replaceAll(',', '.')) ??
        0;
  }

  var _isAmountError = false;
  var _nextButtonEnabled = false;

  Future<String> _generatePredicateBytecode(FuelWallet wallet) async {
    String secret = wallet.privateKey;
    final response = await _dio.get(
      'http://predicatebuilderloabbalancer-12220313.us-east-1.elb.amazonaws.com:8080/predicate_bytes?secret=$secret',
    );

    var bytecode = response.data as String;
    bytecode = bytecode.replaceAll('"', '');

    print('Generated bytecode: $bytecode');
    return bytecode;
  }

  Future<FuelWallet> _generateRandomWallet() {
    return FuelWallet.generateNewWallet(
        networkUrl: BlockchainNetwork.testnet.host);
  }

  @override
  void initState() {
    super.initState();

    _amountTextController.addListener(
          () =>
          setState(() {
            if (_amountTextController.text.contains(',')) {
              _amountTextController.text =
                  _amountTextController.text.replaceAll(",", ".");

              _amountTextController.selection = TextSelection.fromPosition(
                TextPosition(
                  offset: _amountTextController.text.length,
                ),
              );
            }
            final newAmountText = _amountTextController.text;

            _isAmountError = _knownBalance < _amountValue;
            _nextButtonEnabled =
                newAmountText.isNotEmpty && _amountValue != 0 &&
                    !_isAmountError;
          }),
    );

    final assetBalance = context
        .read<BalancesBloc>()
        .state
        .getBalanceByAssetId(widget.tokenBalance.asset);

    _knownBalance = assetBalance.amount;
  }

  @override
  void dispose() {
    _amountFocusNode.dispose();
    _amountTextController.dispose();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FLTScaffold(
      appBar: FLTAppBar(
        title: const Text("Send by QR"),
        centerTitle: true,
        leading: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: FLTIconButton(
            onTap: () {
              context.router.pop();
            },
            icon: SvgPicture.asset(
              Assets.icons.arrows.iosArrowBack,
            ),
          ),
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CoinBalanceWidget(
              balance: _knownBalance,
              currencyShortName: widget.tokenBalance.symbol,
              onMaxTap: () {
                _amountTextController.text = _knownBalance.toString();
                _amountFocusNode.requestFocus();
              },
            ),
            const SizedBox(height: 12),
            FLTMonocoloredPrimaryButton(
              enabled: _nextButtonEnabled,
              onPressed: () async {
                FuelWallet secretWallet = await _generateRandomWallet();
                String predicateBytecode = await _generatePredicateBytecode(
                    secretWallet);
                SendCoinsPredicate predicate = SendCoinsPredicate(
                    BlockchainNetwork.testnet.host, predicateBytecode);
                String predicateBechAddress = await predicate.address();
                FuelWallet accountWallet = await FuelWallet
                    .newFromMnemonicPhrase(
                    networkUrl: BlockchainNetwork.testnet.host,
                    mnemonic: widget.account.seedPhrase!);
                String predicateB256Address = await FuelUtils.b256FromBech32String(predicateBechAddress);
                String txId = await accountWallet.transfer(
                    destinationB256Address: predicateB256Address,
                    fractionalAmount: (_amountValue * 1000000000).toInt(),
                    assetId: "0x0000000000000000000000000000000000000000000000000000000000000000",
                    gasPrice: 1,
                    gasLimit: 10000000,
                    maturity: 0);

                context.router.push(
                  SendByQRRoute(
                    txId: txId,
                    secretWallet: secretWallet,
                    amount: _amountValue,
                    senderAddress: context
                        .read<AccountsBloc>()
                        .state
                        .accounts
                        .first
                        .fuelAddress
                        .bech32Address,
                  ),
                );
              },
              text: "Generate",
            ),
          ],
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(
          children: [
            Expanded(
              child: Center(
                child: CoinAmountInput(
                  controller: _amountTextController,
                  focusNode: _amountFocusNode,
                  hasError: _isAmountError,
                  amount: _amountValue,
                  symbol: widget.tokenBalance.symbol,
                ),
              ),
            ),
            const SizedBox(height: 100),
          ],
        ),
      ),
    );
  }
}
