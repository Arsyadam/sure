module MailSync
  module EventLogger
    module_function

    def log(event, message = nil, level: "info", connection: nil, **metadata)
      MailSyncEvent.log!(
        event: event,
        message: message,
        level: level,
        connection: connection,
        metadata: metadata
      )
    end
  end
end
