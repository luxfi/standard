import { Blockchain } from '@btc-vision/btc-runtime/runtime';
import { revertOnError } from '@btc-vision/btc-runtime/runtime/abort/abort';
import { LuxBridge } from './LuxBridge';

// DO NOT TOUCH THIS.
Blockchain.contract = new LuxBridge();
revertOnError();
