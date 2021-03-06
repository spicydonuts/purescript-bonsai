-- | Purescript interface to Elm Virtual DOM
module Bonsai.VirtualDom
  ( VNode
  , Property
  , Options
  , Patch
  , node
  , text
  , property
  , attribute
  , attributeNS
  , style
  , on
  , onWithOptions
  , defaultOptions
  , lazy
  , lazy2
  , lazy3
  , keyedNode
  , render
  , diff
  , applyPatches
  )
where

import Prelude

import Bonsai.DOM.Primitive (Element)
import Bonsai.Types (BONSAI, Cmd, CmdDecoder, Document, Emitter)
import Control.Monad.Eff (Eff)
import Control.Monad.Eff.Exception (Error)
import Data.Either (Either)
import Data.Foreign (Foreign, toForeign)
import Data.Function.Uncurried (Fn2, Fn3, Fn4, Fn6, runFn2, runFn3, runFn4, runFn6)
import Data.Tuple (Tuple)

-- | An immutable chunk of data representing a DOM node. This can be HTML or SVG.
-- |
-- | It's a functor that maps the Cmds that are emitted by event handlers.
newtype VNode msg =
  VNode Foreign

instance functorVNode :: Functor VNode where
  map = runFn2 mapFn2

-- | Create a DOM node with a tag name, a list of HTML properties that can
-- | include styles and event listeners, a list of CSS properties like `color`, and
-- | a list of child nodes.
node :: forall msg. String -> Array (Property msg) -> Array (VNode msg) -> VNode msg
node =
  runFn3 nodeFn3

foreign import nodeFn3 :: forall msg. Fn3 String (Array (Property msg)) (Array (VNode msg)) (VNode msg)


-- | Just put plain text in the DOM. It will escape the string so that it appears
-- | exactly as you specify.
-- |
-- |    text "Hello World!"
foreign import text :: forall msg. String -> VNode msg

-- | This function is useful when nesting components with [the Elm
-- | Architecture](https://github.com/evancz/elm-architecture-tutorial/). It lets
-- | you transform the messages produced by a subtree.
-- |
-- | Say you have a node named `button` that produces `()` values when it is
-- | clicked. To get your model updating properly, you will probably want to tag
-- | this `()` value like this:
mapNode :: forall a msg. (a -> msg) -> VNode a-> VNode msg
mapNode =
  runFn2 mapFn2

foreign import mapFn2 :: forall a msg. Fn2 (a -> msg) (VNode a) (VNode msg)

-- PROPERTIES


-- | When using HTML and JS, there are two ways to specify parts of a DOM node.
-- |
-- |  1. Attributes &mdash; You can set things in HTML itself. So the `class`
-- |     in `<div class="greeting"></div>` is called an *attribute*.
-- |
-- |  2. Properties &mdash; You can also set things in JS. So the `className`
-- |     in `div.className = 'greeting'` is called a *property*.
-- |
-- | So the `class` attribute corresponds to the `className` property. At first
-- | glance, perhaps this distinction is defensible, but it gets much crazier.
-- | *There is not always a one-to-one mapping between attributes and properties!*
-- | Yes, that is a true fact. Sometimes an attribute exists, but there is no
-- | corresponding property. Sometimes changing an attribute does not change the
-- | underlying property. For example, as of this writing, the `webkit-playsinline`
-- | attribute can be used in HTML, but there is no corresponding property!

newtype Property msg =
  Property Foreign

-- | Create arbitrary *properties*.
-- |
-- |    import JavaScript.Encode as Json
-- |
-- |    greeting : Html
-- |    greeting =
-- |        node "div" [ property "className" (Json.string "greeting") ] [
-- |          text "Hello!"
-- |        ]
-- |
-- | Notice that you must give the *property* name, so we use `className` as it
-- | would be in JavaScript, not `class` as it would appear in HTML.
property :: forall a msg. String -> a -> Property msg
property key value =
  runFn2 propertyFn2 key (toForeign value)

foreign import propertyFn2
  :: forall msg
  .  Fn2 String Foreign (Property msg)


-- | Create arbitrary HTML *attributes*. Maps onto JavaScript’s `setAttribute`
-- | function under the hood.
-- |
-- | Notice that you must give the *attribute* name, so we use `class` as it would
-- | be in HTML, not `className` as it would appear in JS.
attribute :: forall msg. String -> String -> Property msg
attribute =
  runFn2 attributeFn2

foreign import attributeFn2 :: forall msg. Fn2 String String (Property msg)


-- | Would you believe that there is another way to do this?! This corresponds
-- | to JavaScript's `setAttributeNS` function under the hood. It is doing pretty
-- | much the same thing as `attribute` but you are able to have "namespaced"
-- | attributes. This is used in some SVG stuff at least.
attributeNS :: forall msg. String -> String -> String -> Property msg
attributeNS = runFn3 attributeFn3

foreign import attributeFn3 :: forall msg. Fn3 String String String (Property msg)


-- | Specify a list of styles.
foreign import style :: forall msg. Array (Tuple String String) -> Property msg


-- EVENTS

-- internal concrete alias so we can get it into javascript
type CmdDecoderMap eff a b = (a -> b) -> CmdDecoder eff a -> CmdDecoder eff b
cmdDecoderMap :: forall eff a b. CmdDecoderMap eff a b
cmdDecoderMap fn decoder =
  map (map (map fn)) decoder


-- | Create a custom event listener.
on :: forall eff msg. String -> (CmdDecoder eff msg) -> Property msg
on eventName decoder =
  runFn3 onFn3 eventName defaultOptions decoder

foreign import onFn3
  :: forall eff msg
  .  Fn3 String Options (CmdDecoder eff msg) (Property msg)


-- | Same as `on` but you can set a few options.
onWithOptions :: forall aff msg. String -> Options -> CmdDecoder aff msg -> Property msg
onWithOptions =
  runFn3 onFn3



-- | Options for an event listener. If `stopPropagation` is true, it means the
-- | event stops traveling through the DOM so it will not trigger any other event
-- | listeners. If `preventDefault` is true, any built-in browser behavior related
-- | to the event is prevented. For example, this is used with touch events when you
-- | want to treat them as gestures of your own, not as scrolls.
type Options =
  { stopPropagation :: Boolean
  , preventDefault :: Boolean
  }


-- | Everything is `False` by default.
-- |
-- |     defaultOptions =
-- |         { stopPropagation = False
-- |         , preventDefault = False
-- |         }
defaultOptions :: Options
defaultOptions =
  { stopPropagation: false
  , preventDefault: false
  }


-- OPTIMIZATION


-- | A performance optimization that delays the building of virtual DOM nodes.
-- |
-- | Calling `(view model)` will definitely build some virtual DOM, perhaps a lot of
-- | it. Calling `(lazy view model)` delays the call until later. During diffing, we
-- | can check to see if `model` is referentially equal to the previous value used,
-- | and if so, we just stop. No need to build up the tree structure and diff it,
-- | we know if the input to `view` is the same, the output must be the same!
lazy :: forall a msg. (a -> VNode msg) -> a -> VNode msg
lazy =
  runFn2 lazyFn2

foreign import lazyFn2
  :: forall a msg
  .  Fn2 (a -> VNode msg) a (VNode msg)

-- | Same as `lazy` but checks on two arguments.
lazy2 :: forall a b msg. (a -> b -> VNode msg) -> a -> b -> VNode msg
lazy2 =
  runFn3 lazy2Fn3

foreign import lazy2Fn3
  :: forall a b msg
  .  Fn3 (a -> b -> VNode msg) a b (VNode msg)

-- | Same as `lazy` but checks on three arguments.
lazy3 :: forall a b c msg. (a -> b -> c -> VNode msg) -> a -> b -> c -> VNode msg
lazy3 =
  runFn4 lazy3Fn4

foreign import lazy3Fn4
  :: forall a b c msg
  .  Fn4 (a -> b -> c -> VNode msg) a b c (VNode msg)


-- | Works just like `node`, but you add a unique identifier to each child
-- | node. You want this when you have a list of nodes that is changing: adding
-- | nodes, removing nodes, etc. In these cases, the unique identifiers help make
-- | the DOM modifications more efficient.
keyedNode
  :: forall msg
  .  String
  -> Array (Property msg)
  -> Array (Tuple String (VNode msg))
  -> VNode msg
keyedNode =
  runFn3 keyedNodeFn3

foreign import keyedNodeFn3 ::
  forall msg.
  Fn3 String (Array (Property msg)) (Array (Tuple String (VNode msg))) (VNode msg)


-- | Render a virtual dom node to a DOM Element.
-- |
-- | Initial step - the whole point in a VDom is the diffing
-- | and patching.  So after rendering once, diff and applyPatches
-- | should be used.
render
  :: forall aff msg
  .  Document
  -> Emitter aff msg
  -> VNode msg
  -> Element
render doc = runFn4 renderFn4 doc cmdMap

foreign import renderFn4
  :: forall aff a msg
  .  Fn4 Document (CmdMap aff a msg) (Emitter aff msg) (VNode msg) Element

-- internal concrete alias so we can get it into javascript
type CmdMap aff a b = (a -> b) -> (Either Error (Cmd aff a)) -> (Either Error (Cmd aff b))
cmdMap :: forall aff a b. CmdMap aff a b
cmdMap f a = map (map f) a

-- | A Patch for efficient updates.
newtype Patch msg =
  Patch Foreign

-- | Compute a patch between the old vnode representation and the new one.
diff :: forall msg. VNode msg -> VNode msg -> Patch msg
diff = runFn2 diffFn2

foreign import diffFn2
  :: forall msg
  .  Fn2 (VNode msg) (VNode msg) (Patch msg)

-- | Apply a diff between VDoms to the DOM element.
-- |
-- | The DOM element should be the one from the last
-- | diff/applyPatches pass, or the initially rendered one.
applyPatches
  :: forall eff aff msg
  .  Document
  -> Emitter aff msg
  -> Element
  -> VNode msg
  -> Patch msg
  -> Eff (bonsai::BONSAI|eff) Element
applyPatches doc emitter domNode oldVirtualNode patches =
  pure $ runFn6 applyPatchesFn6 doc cmdMap emitter domNode oldVirtualNode patches

foreign import applyPatchesFn6
  :: forall aff a msg
  .  Fn6 Document (CmdMap aff a msg) (Emitter aff msg) Element (VNode msg) (Patch msg) Element
