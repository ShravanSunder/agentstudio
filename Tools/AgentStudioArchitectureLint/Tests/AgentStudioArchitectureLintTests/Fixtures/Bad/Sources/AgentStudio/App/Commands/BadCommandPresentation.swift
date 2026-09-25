struct BadCommandPresentation {
    static func resolve(command: Int, dispatcher: CommandDispatcher) -> Bool {
        dispatcher.canDispatch(command)
    }
}
