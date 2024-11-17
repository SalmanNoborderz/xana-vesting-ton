import { CompilerConfig } from '@ton/blueprint';

export const compile: CompilerConfig = {
    lang: 'tact',
    target: 'contracts/VestingV2.tact',
    options: {
        debug: true,
    },
};
