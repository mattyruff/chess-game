import SwiftUI
import ChessCore

private enum Palette {
    static let background = Color(red: 0.055, green: 0.075, blue: 0.066)
    static let panel = Color(red: 0.085, green: 0.110, blue: 0.097)
    static let ivory = Color(red: 0.94, green: 0.91, blue: 0.83)
    static let gold = Color(red: 0.77, green: 0.64, blue: 0.40)
    static let muted = Color(red: 0.57, green: 0.64, blue: 0.59)
}

struct ContentView: View {
    @StateObject private var game = GameModel()
    @Environment(\.scenePhase) private var scenePhase
    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    header
                    if geometry.size.width > 900 {
                        HStack(alignment: .top, spacing: 24) {
                            boardArea
                            GamePanel(game: game, online: game.online).frame(width: 300)
                        }
                    } else {
                        boardArea
                        GamePanel(game: game, online: game.online)
                    }
                    HStack {
                        Text("A CLASSIC, IN EVERY DIMENSION")
                        Spacer()
                        Text("ROYAL CHESS")
                    }
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .tracking(2).foregroundStyle(Palette.muted)
                }
                .padding(geometry.size.width < 600 ? 18 : 32)
                .frame(maxWidth: 1440).frame(maxWidth: .infinity)
            }
            .background(Palette.background)
        }
        .tint(Palette.gold)
        .onChange(of: scenePhase) { phase in
            if phase == .active && game.mode == .online && game.online.matchID != nil { game.online.refresh() }
        }
        .foregroundStyle(Palette.ivory)
        .sheet(isPresented: $game.showsSetup) { NewGameView(game: game) }
        .sheet(isPresented: Binding(get: { !game.promotionChoices.isEmpty }, set: { if !$0 { game.cancelPromotion() } })) {
            PromotionView(game: game)
        }
        .alert("Unable to send move", isPresented: Binding(get: { game.onlineError != nil }, set: { if !$0 { game.onlineError = nil } })) {
            Button("OK", role: .cancel) { game.onlineError = nil }
        } message: { Text(game.onlineError ?? "Please try again.") }
    }

    private var header: some View {
        HStack(alignment: .center) {
            HStack(spacing: 12) {
                Text("♔").font(.system(size: 46)).foregroundStyle(Palette.gold)
                VStack(alignment: .leading, spacing: 3) {
                    Text("ROYAL CHESS").font(.system(size: 23, weight: .regular, design: .serif)).tracking(3)
                    Text("THE TIMELESS GAME.").font(.system(size: 9, weight: .medium)).tracking(3).foregroundStyle(Palette.muted)
                }
            }
            Spacer(minLength: 10)
            Button { game.showsSetup = true } label: {
                Image(systemName: "slider.horizontal.3").font(.title3).padding(12)
            }
            .buttonStyle(.plain)
            .background(Palette.panel, in: RoundedRectangle(cornerRadius: 12))
            .accessibilityLabel("Game options")
        }
    }

    private var boardArea: some View {
        VStack(spacing: 0) {
            playerLabel(side: game.perspective.opponent)
            ChessBoardView(controller: game.board)
                .aspectRatio(1.08, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 18))
                .accessibilityLabel("3D chessboard. Select a piece, then a highlighted destination.")
            playerLabel(side: game.perspective)
        }
        .padding(12)
        .background(Palette.panel, in: RoundedRectangle(cornerRadius: 24))
        .overlay(RoundedRectangle(cornerRadius: 24).stroke(Palette.gold.opacity(0.12), lineWidth: 1))
    }

    private func playerLabel(side: Side) -> some View {
        HStack(spacing: 10) {
            Circle().fill(side == .white ? Palette.ivory : Color.black)
                .frame(width: 12, height: 12)
                .overlay(Circle().stroke(.white.opacity(0.22), lineWidth: 1))
            Text(side.title).font(.system(size: 13, weight: .semibold))
            if game.mode == .computer {
                Text(side == game.humanSide ? "YOU" : "\(game.difficulty.title.uppercased()) AI")
                    .font(.system(size: 9, weight: .medium)).tracking(1.3).foregroundStyle(Palette.muted)
            }
            Spacer()
            if !game.isGameOver && game.position.sideToMove == side {
                Circle().fill(Palette.gold).frame(width: 5, height: 5)
                Text("TO MOVE").font(.system(size: 9, weight: .medium)).tracking(1.4).foregroundStyle(Palette.gold)
            }
        }.padding(.horizontal, 12).padding(.vertical, 15)
    }
}

private struct GamePanel: View {
    @ObservedObject var game: GameModel
    @ObservedObject var online: OnlineGame
    @State private var confirmsLeaving = false
    @State private var leaveError: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 12) {
                eyebrow("AT THE TABLE")
                HStack(spacing: 10) {
                    if game.isThinking || game.isSubmitting { ProgressView().controlSize(.small) }
                    Text(game.status).font(.system(size: 26, weight: .regular, design: .serif))
                }
                Text(game.detail).font(.system(size: 13)).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 7) {
                    Image(systemName: game.mode == .computer ? "cpu" : game.mode == .online ? "network" : "person.2")
                    Text(game.mode.rawValue)
                    if game.mode == .computer { Text("· \(game.difficulty.title)") }
                }.font(.system(size: 11)).foregroundStyle(Palette.gold).padding(.top, 5)
            }
            Rectangle().fill(Palette.gold.opacity(0.15)).frame(height: 1)
            if game.mode == .online { onlineControls }
            VStack(spacing: 10) {
                Button { game.showsSetup = true } label: {
                    Label("New game", systemImage: "plus").frame(maxWidth: .infinity).padding(.vertical, 7)
                }.buttonStyle(.borderedProminent).foregroundStyle(Palette.background)
                HStack(spacing: 10) {
                    Button { game.undo() } label: { Label("Undo", systemImage: "arrow.uturn.backward").frame(maxWidth: .infinity) }
                        .disabled(!game.canUndo)
                    Button { game.flipBoard() } label: { Label("Rotate", systemImage: "arrow.triangle.2.circlepath").frame(maxWidth: .infinity) }
                }.buttonStyle(.bordered).font(.system(size: 12))
            }
            VStack(alignment: .leading, spacing: 14) {
                HStack { eyebrow("MOVE RECORD"); Spacer(); Text("\(game.records.count) plies").font(.caption2).foregroundStyle(Palette.muted) }
                if game.records.isEmpty {
                    VStack(spacing: 8) {
                        Text("♙").font(.system(size: 32)).foregroundStyle(Palette.gold.opacity(0.6))
                        Text("Every great game starts\nwith a single move.").multilineTextAlignment(.center).font(.system(size: 12, design: .serif)).foregroundStyle(Palette.muted)
                    }.frame(maxWidth: .infinity).padding(.vertical, 22)
                } else {
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(spacing: 0) {
                                ForEach(0..<((game.records.count + 1) / 2), id: \.self) { row in
                                    HStack {
                                        Text("\(row + 1).").foregroundStyle(Palette.muted).frame(width: 28, alignment: .leading)
                                        Text(game.records[row * 2].text).frame(maxWidth: .infinity, alignment: .leading)
                                        Text(row * 2 + 1 < game.records.count ? game.records[row * 2 + 1].text : "—").frame(maxWidth: .infinity, alignment: .leading)
                                    }.font(.system(size: 12, design: .monospaced)).padding(.vertical, 10).padding(.horizontal, 8)
                                        .background(row.isMultiple(of: 2) ? Color.white.opacity(0.025) : .clear).id(row)
                                }
                            }
                        }.frame(height: 180)
                            .onChange(of: game.records.count) { _ in
                                withAnimation { proxy.scrollTo((game.records.count - 1) / 2, anchor: .bottom) }
                            }
                    }
                }
            }
            if let notice = game.storageNotice { Text(notice).font(.caption).foregroundStyle(Palette.gold) }
            Text("Classic rules. Castling, en passant, and your choice of promotion.")
                .font(.system(size: 11)).foregroundStyle(Palette.muted).lineSpacing(4)
        }
        .padding(24).background(Palette.panel, in: RoundedRectangle(cornerRadius: 24))
        .overlay(RoundedRectangle(cornerRadius: 24).stroke(Palette.gold.opacity(0.12), lineWidth: 1))
        .sheet(item: $online.authentication) { GameCenterAuthenticationView(presentation: $0) }
        .confirmationDialog("Leave this online match? An unfinished match counts as a resignation.", isPresented: $confirmsLeaving, titleVisibility: .visible) {
            Button(online.isFinished ? "Close match" : "Resign match", role: .destructive) {
                Task {
                    do { try await online.leave() }
                    catch { leaveError = error.localizedDescription }
                }
            }
        }
        .alert("Unable to leave match", isPresented: Binding(get: { leaveError != nil }, set: { if !$0 { leaveError = nil } })) {
            Button("OK", role: .cancel) { leaveError = nil }
        } message: { Text(leaveError ?? "Try again.") }
    }

    private var onlineControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("GAME CENTER").font(.system(size: 10, weight: .semibold)).tracking(2).foregroundStyle(Palette.gold)
            Text(online.status).font(.caption).foregroundStyle(Palette.muted)
            if !online.isAuthenticated {
                Button("Sign in to Game Center") { online.authenticate() }
            } else {
                if online.matchID == nil {
                    Button("Find an opponent") { online.findMatch() }.disabled(online.isBusy)
                } else {
                    Text("You play \(online.localSide.title.lowercased()) · \(online.opponentName)").font(.caption)
                    Button("Refresh match") { online.refresh() }.disabled(online.isBusy)
                    Button(online.isFinished ? "Close match" : "Resign match", role: .destructive) { confirmsLeaving = true }.disabled(online.isBusy)
                }
                Button("Load your matches") { online.loadMatches() }.disabled(online.isBusy)
                ForEach(online.matches) { match in
                    Button { online.selectMatch(match) } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(match.title).font(.caption)
                            Text(match.detail).font(.caption2).foregroundStyle(Palette.muted)
                        }
                    }.disabled(online.isBusy)
                }
            }
            Text("Online games are turn based. You can leave and resume your match later.")
                .font(.caption2).foregroundStyle(Palette.muted)
        }.buttonStyle(.bordered)
    }

    private func eyebrow(_ text: String) -> some View {
        Text(text).font(.system(size: 10, weight: .medium)).tracking(2).foregroundStyle(Palette.muted)
    }
}

private struct NewGameView: View {
    @ObservedObject var game: GameModel
    @Environment(\.dismiss) private var dismiss
    @State private var mode: PlayMode = .computer
    @State private var difficulty: Difficulty = .intermediate
    @State private var side: Side = .white
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack {
                Text("Your next game").font(.system(size: 29, design: .serif))
                Spacer()
                Button { dismiss() } label: { Image(systemName: "xmark") }.buttonStyle(.plain).accessibilityLabel("Close game options")
            }
            Text("Choose your opponent. Take your seat.").foregroundStyle(Palette.muted).font(.subheadline)
            Picker("Play against", selection: $mode) {
                ForEach(PlayMode.allCases) { Text($0.rawValue).tag($0) }
            }.pickerStyle(.segmented)
            if mode == .computer {
                VStack(alignment: .leading, spacing: 12) {
                    Text("DIFFICULTY").font(.caption2).tracking(2).foregroundStyle(Palette.gold)
                    Picker("Difficulty", selection: $difficulty) {
                        ForEach(Difficulty.allCases, id: \.self) { Text($0.title).tag($0) }
                    }.pickerStyle(.segmented)
                    Text(difficulty.explanation).font(.subheadline).foregroundStyle(Palette.muted).frame(minHeight: 44, alignment: .topLeading)
                    Picker("Play as", selection: $side) {
                        Text("White · moves first").tag(Side.white)
                        Text("Black").tag(Side.black)
                    }
                }
            } else if mode == .online {
                Text("Match with another player through Game Center. Online games save each turn so you can resume later. Colors are assigned when you join.")
                    .foregroundStyle(Palette.muted).font(.subheadline)
            } else {
                Text("Share one device. White moves first; rotate the board whenever you switch seats.")
                    .foregroundStyle(Palette.muted).font(.subheadline)
            }
            Button {
                game.start(mode: mode, difficulty: difficulty, side: side)
                dismiss()
            } label: {
                Text(mode == .online ? "Open online play" : "Start game").frame(maxWidth: .infinity).padding(.vertical, 9)
            }.buttonStyle(.borderedProminent).tint(Palette.gold).foregroundStyle(Palette.background)
            if !game.records.isEmpty && game.mode != .online {
                Text("Starting a new game replaces your current game.").font(.caption).foregroundStyle(Palette.muted)
            }
        }
        .padding(30).frame(idealWidth: 470).background(Palette.background).foregroundStyle(Palette.ivory)
        .onAppear { mode = game.mode; difficulty = game.difficulty; side = game.humanSide }
    }
}

private struct PromotionView: View {
    @ObservedObject var game: GameModel
    var body: some View {
        VStack(spacing: 22) {
            Text("A pawn’s promotion").font(.system(size: 27, design: .serif))
            Text("Choose the piece that takes its place.").foregroundStyle(Palette.muted)
            HStack(spacing: 14) {
                ForEach([PieceKind.queen, .rook, .bishop, .knight], id: \.self) { kind in
                    Button { game.promote(to: kind) } label: {
                        VStack(spacing: 6) {
                            Text(kind.symbol).font(.system(size: 40))
                            Text(kind.rawValue.capitalized).font(.caption)
                        }.frame(width: 62).padding(.vertical, 12)
                    }.buttonStyle(.bordered).tint(Palette.gold)
                }
            }
            Button("Cancel") { game.cancelPromotion() }.foregroundStyle(Palette.muted)
        }.padding(28).background(Palette.background).foregroundStyle(Palette.ivory)
    }
}
