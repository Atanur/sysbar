import Foundation
import Testing
@testable import SysbarCore

private let nettopOutput = """
time,,interface,state,bytes_in,bytes_out,rx_dupe,rx_ooo,re-tx,rtt_avg,rcvsize,tx_win,tc_class,tc_mgt,cc_algo,P,C,R,W,arch,
00:00:00.000001,Safari.123,,,1200,340,0,0,0,,,,,,,,,,,,
00:00:00.000002,Acme, Inc.456,,,50,60,0,0,0,,,,,,,,,,,,
00:00:00.000003,Safari.123,,,100,20,0,0,0,,,,,,,,,,,,
00:00:00.000004,com.apple.WebKit.Networking.789,,,7,8,0,0,0,,,,,,,,,,,,
00:00:00.000005,mDNSResponder.999,en0,ESTAB,10,20,0,0,0,,,,,,,,,,,,
not a row
"""

@Suite struct NettopParserTests {
    @Test func sumsEachProcessesCumulativeCounters() {
        let counters = NettopParser.parse(nettopOutput)

        #expect(counters[123] == ByteCounters(received: 1_300, sent: 360))
        #expect(counters[456] == ByteCounters(received: 50, sent: 60))
        #expect(counters[789] == ByteCounters(received: 7, sent: 8))
        // A socket row, not a per-process summary, is skipped.
        #expect(counters[999] == nil)
    }

    @Test func emptyOrUnreadableOutputHasNoProcesses() {
        #expect(NettopParser.parse("").isEmpty)
        #expect(NettopParser.parse("time,,interface,state,bytes_in,bytes_out,\n").isEmpty)
        #expect(NettopParser.parse("nonsense\nmore nonsense").isEmpty)
    }
}
