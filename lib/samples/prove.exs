statechart do
  states do
      state "s21", :initial do
        states do
          state "a" do
            states do
              state "x", :initial do
                entry fn context -> do
                  Map.put(context, :foo, "bar")
                end
              end
            end
          end
          state "b" do
            state "y", :initial
          end
        end
        transitions do

        end
      end
      state "s22"
      state "exit", :final do
        entry &__MODULE__.exit_entry/1
      end
      state "h*", :deep_history
  end
  transitions do
      transition "a", target: "s1"
  end
end

conversation "authentication" do
  commands do
    command "cancel", key: "F9", text: gettext("Cancel"), voice: gettext("cancel") do
      ctx
      |> exit("cancelled")
    end
    command "help", key: "F1", text: gettext("Help"), voice: gettext("help") do
      ctx
      |> say("Please authenticate yourself for entering in Voicering")
    end
  end

  dialog "ask_username" do
    question do
      ctx
      |> say("what's your username?")
      |> content("<h1>Please input your username</h1>")
    end

    answer do
      if answer == "carlo" do
        ctx
        |> put("username", "carlo")
        |> dialog("password")
      else
        ctx
        |> say("wrong username")
        |> error("I don't known username #{answer}")
      end
    end
  end

  dialog "password" do
    question do
      |> say("what's your password?")
      |> content("<h1>Please input password for #{ctx["username"]}</h1>")
    end

    answer do
      if answer == "1234" do
        ctx
        |> delete("username")
        |> delete("username")
        |> put("user", "carlo")
        |> exit("authenticated")
      else
        |> say("wrong password")
        |> error("Wrong password for username #{ctx["username"]}")
      end
    end
  end
end
